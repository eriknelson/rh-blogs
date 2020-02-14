# Running Cluster Application Migrations in a Disconnected Environment

**TODO: Credit 4.3 documentation page on disconnected**

## Pre-requisites

* podman
* oc client tool > 4.3.1
* openssl
* [offline-cataloger](https://github.com/kevinrizza/offline-cataloger)
* [operator-courier](https://github.com/operator-framework/operator-courier)

## Initial Assumptions

Since the Cluster Application Migration suite can be configured in a number
of different topologies, we're going to assume a standard deployment scenario
where the customer has a 3.11 cluster running a workload that they desire to
migrate to an OpenShift 4.3.1 cluster. We'll assume the OpenShift 4.3.1 cluster
has already been provisioned and installed, but neither the 3.11 cluster, or
the 4.3.1 cluster have network access to the outside world. Of particular importance,
however, is that the individual performing the migration *does* have external
network access, as well as network access to both the 3.11 cluster and the 4.3.1
cluster. Let's call the 3.11 cluster the "source" cluster, and the 4.3.1 cluster
the "destination" cluster. When CAM is installed on a cluster, it is typically
installed in one of two configurations:

1) A **control cluster** that contains all CAM components: the controller which
orchestrates migrations and presents the CAM API surface to the cluster that it
has been installed in, the UI from which a user can drive a migration, and the
underlying velero installation that will be used to restore a migrated application.

2) A **remote cluster** that runs the underlying velero infrastructure which accepts
instructions from the control cluster to export a running workload. The controller
and UI components should be disabled in a remote cluster. One additionally
unique property of a remote cluster is that a "mig" `ServiceAccount` is created
and is granted a `cluster-admin` binding. This `ServiceAccount` token is registered
along with the coordinates to the remote cluster with the control cluster so that
the control cluster's "controller" may interface with the remote cluster's APIs
as that `ServiceAccount`.

> NOTE: The control cluster does not necessarily have to be the destination cluster
for the migrated workload, although for the majority of users, this will be true.
It is possible to host your control cluster in a third cluster, and orchestrate
a migration between cluster `Foo` and `Bar` (both remote clusters), while the
control cluster lives in a cluster `Baz`. For the purposes of this article, the
control cluster can, and will act as the target cluster for the migration workload.

We will be using the CAM operator to install all components for both clusters,
regardless of the presence of OLM.

> NOTE: You may see `o` used in lieu of `oc`. This is because I have an alias
set up for convenience.

## Installing the CAM in the control cluster (4.3.1)

On an OpenShift 4.3.1 cluster, OLM is present and normally exposes Red Hat's
catalog of optional operators that extend the cluster's functionality. In the
case of a disconnected cluster, you will not have access to this external catalog.
In order to make the catalog of operators available to your cluster, you will
need to build your own catalog and then mirror all relevant images to an image
registry that has been made available to both clusters.

To begin, let's disable all the original OperatorSources that OCP 4 comes
configured with by default (since you will not be able to connect with the
remote catalog).

`oc edit operatorhub cluster`

Then edit the spec to read:

```
spec:
  disableAllDefaultSources: true
```

This will effectively clear OLM's catalog of any operators so we can install
our own custom build catalog.

### Setting up a shared registry

As mentioned before, you will need to run your own internal registry that
will host the inventory of images necessary for the cluster to deploy CAM.
This could be your own registry you have set up yourself that is network
addressable by your control cluster. In our case, we'll simply set up a registry
as a sample workload backed by a PV and host our images there.

You can find an [example registry manifest](#) at this blog's [github page](#).

If you checkout the github project and run the following command, you should
have an (unsecured) registry available to host your images internally:

`oc create -f $YOUR_CHECKOUT/registry.yml`

> NOTE: Take time to inspect this registry file and tweak as you would like.
By default, a 32Gi PVC is created.

Running a few verification oc commands, we can see that we have a docker registry
pod runing in the `nsk-discon-test` namespace, along with an external route,
and a 32Gi PVC bound to the pod:

```
oc get
# oc get pods; oc get pvc; oc get routes
NAME                        READY   STATUS    RESTARTS   AGE
registry-865966d8fd-gb2nd   1/1     Running   0          2m43s
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
registry   Bound    pvc-0c9a17fa-2599-4aba-9f2d-aaf5878cfeeb   32Gi       RWO            gp2            2m43s
NAME       HOST/PORT                                                                         PATH   SERVICES   PORT        TERMINATION     WILDCARD
registry   <<REGISTRY_ROUTE>>          registry   port-5000   edge/Redirect   None
```


**TODO**: Is this actually necessary if we're adding the CA bundle as trusted
to the machine?

Be sure to add this registry's route to the list of your insecure registries on
the machine you're using to mirror the images (probably your laptop). This
can be found in `/etc/containers/registries.conf`. Additionally, it's probably
useful to export the snipped `<<REGISTRY_ROUTE>>` from the output above that
will be your registry's specific address (replace `<<REGISTRY_ROUTE>>` with your address):

`export REGISTRY_ROUTE=<<REGISTRY_ROUTE>>`

We will refer to this address from now on as `$REGISTRY_ROUTE`.

### Installing your registry's CA bundle as trusted

Before we can build our own catalog and mirror our images into our registry,
the CA needs to be installed as trusted by the machine that will be executing
the mirror commands. The following script can be executed to install your
registry's CA as a trusted authority:

**TODO** What is the more "oc" direct way of exporing this without using openssl?

```sh
openssl s_client -showcerts -servername server \
  -connect "$REGISTRY_ROUTE:443" > /tmp/my-registry.crt
sudo cp /tmp/my-registry.crt /etc/pki/ca-trust/source/anchors/my-registry.crt
sudo update-ca-trust
```

**TODO: This will be completely uncecessary with 4.4 tooling now that they've
added a skip verification option**

### Build a CatalogSource containing the operator metadata for OLM

**TODO: Mention RFE to enhance tooling to support pulling specific operators?
https://issues.redhat.com/browse/RFE-591**

**TODO: It is currently impossible to run ocs in a disconnected environment because
the images will be impossible to mirror via oc adm catalog mirror due to their
metadata missing relatedImages**

**TODO: oc adm catalog build 4.3.1 completely ignores the --manifest-dir argument...
https://bugzilla.redhat.com/show_bug.cgi?id=1772942**


The next step in the process is to build your own `CatalogSource` containing
the operator metadata that OLM would normally pull remotely from Red Hat.
Since we only care about the cam-operator, we're going to download all of Red
Hat's operator catalog, but remove everything except for the cam-operator.

Operator metadata can be downloaded and cataloged locally using the
`offline-cataloger` tool mentioned in the pre-requisites. In addition to this
tool, you will also need to generate a quay API token via quay.io, and export
this token into your enviornment.

`export QUAY_TOKEN=<your-quay-token>`

For example: `export QUAY_TOKEN='basic <blob>'`

Navigate to a known directory and run the following command to download the
Red Hat operator metadata:

`offline-cataloger generate-manifests -a "$QUAY_TOKEN" redhat-operators`

You should end up with a `manifests-XXX` directory filled with all of the operator
metadata that Red Hat currently publishes. To clean this of all but the cam-operator,
run the following command:

`cd <your-manifest-dir>; ls -1 | grep -v cam-operator | xargs -I{} rm {}`

**TODO: Because I don't have a way to cut down on what's built with the
oc tooling (feature missing), and the --manifest-dir argument doesn't work with
oc 4.3.1 tooling, I need to actually REPUBLISH this manifest to my own app
registry, and then build a catalog source from that. I should be able to just
build the catalog source from the local disk. This whole following section
should be ripped out.**

Now that we've processed our catalog on disk to strictly be the cam-operator,
we can ship this off to quay, from which we can use the oc tooling to build
and push a `CatalogSource` image to your cluster's internal registry. To do
this, we'll use a tool called operator courier.

Running a tree command on your manifests directory, you'll see the overall
layout, and the directory you'll ultimately use to push your operator's metadata
to quay. As an example:

```
# tree -L 3 ./manifests-497096358
./manifests-497096358
└── cam-operator
    └── cam-operator-uplmhfud
        ├── mig-operator.package.yaml
        ├── v1.0.0
        ├── v1.0.1
        ├── v1.1.0
        └── v1.1.1

operator-courier --verbose push ./manifests-497096358/cam-operator/cam-operator-uplmhfud eriknelson cam-operator 0.1.0 "$QUAY_TOKEN"
```

> IMPORTANT: If this appregistry did not already exist, Quay will create it as a private
appregistry by default. It is imperative that you navigate through the quay UI
to select your new app registry and configure its settings to mark it public.

**TODO: Insert screenshots**

This command packaged up and pushed our operator metadata to our own appregistry,
in this case "eriknelson". From here, we're able to use the oc client tooling to
build and push a `CatalogSource` image based on our personal appregistry.

NOTE: You should replace "eriknelson" with your own quay namespace name.

```
oc adm catalog build \
  --appregistry-endpoint https://quay.io/cnr \
  --appregistry-org eriknelson \
  --to=$REGISTRY_ROUTE/appregistries/eriknelson:v1
```

Using `oc adm catalog build`, it downloaded the metadata we pushed to our own
appregistry, build a `CatalogSource` image, and pushed that image to the exposed
registry route. Although the image resides in our registry on the control cluster,
the `CatalogSource` must still be deployed so it can expose the packages that it
has available to OLM via its grpc API.

### Mirroring all operator and operand images

Of course, the `CatalogSource` only exposes the metadata about your operator
to OLM. We also must mirror our operator's image, as well as all of the images
that the operator itself will deploy (its operands, expressed as `relatedImages`).

```
oc adm catalog mirror \
  $REGISTRY_ROUTE/appregistries/eriknelson:v1 \
  $REGISTRY_ROUTE/openshift
```

### Configuring your control cluster to deploy from its own registry

At this point you have your `CatalogSource` and all of your required images
mirror'd into your cluster and available via the registry that we created, but
you still must configure OCP itself to defer to these images when external
images are referenced. There is a specific object desinged for this purpose
called the `ImageControlSourcePolicy`. Conveniently, the above mirror command
outputs a directory by default from wherever it was run that contains this
object. In my case, it was `eriknelson-manifests`.

> IMPORTANT: Before you create this object, you should know that it will change your
`MachineConfig` because it needs to manipulate underlying files on each of the
nodes. This means the nodes **will be rebooted** following their update. It is
likely you will experience some API server instability during this time.

Running `oc create -f ./eriknelson-manifests/imageContentSourcePolicy.yaml`

At this point you must wait for the new `MachineConfig` to roll out to each of
your nodes, which can take some time depending on the size of your cluster.
You can monitor the progress of this rollout with the following command, noting
the current config, and desired config differences. It should have successfully
finished once all of the current configs match the desired configs:

`watch 'oc describe node -l node-role.kubernetes.io/worker= | grep -e Name: -e rendered'`

**TODO: Is there any way this can be in a batch so there is only one rolling
restart of the entire cluster?**

Once the ICSP change has been rolled out to all the notes, you must now whitelist
the registry that you have configured as an insecure registry so the cluster will
not refuse images from an unverified registry:

```
export WHITELIST_PATCH="{\"spec\":{\"registrySources\":{\"insecureRegistries\":[\"$REGISTRY_ROUTE\"]}}}"
oc patch images.config.openshift.io/cluster -p="$WHITELIST_PATCH" --type=merge
```

Unfortunately this patch will also mutate the `MachineConfig` and also require
an additional rollout. Again you should wait until this is complete, and can
monitor it's progress with the following command:

`watch 'oc describe node -l node-role.kubernetes.io/worker= | grep -e Name: -e rendered'`

Following these procedures, your cluster should now have your personal registry
with all of your mirror'd images, and you have told OCP to defer to this registry
when an application requests one of these images instead of pulling from Red Hat's
external registry.

### Deploying your internal CatalogSource and connecting to OLM

Earlier in the process, we built our own `CatalogSource` image and pushed it
to our registry. The image is safely stored there, but it must be deployed to
expose its API to OLM, therefore alerting OLM to it's contents and making the
operators it contains available for cluster deployment. To do this, first you'll
need to retrieve the sha of your custom `CatalogSource` image. This can be
retrieved using podman and inspecting the image's digest:

> NOTE: Rememeber this pull spec must match the location that you originally
build and pushed your `CatalogSource` image to. For your specific case, it will
likely be different.

First use podman to ensure that you have the image locally, and then you will
be able to inspect it to determine its fully qualified name:
```
podman pull $REGISTRY_ROUTE/appregistries/eriknelson:v1

podman inspect \
    --format='{{index .RepoDigests 0}}' \
    $REGISTRY_ROUTE/appregistries/eriknelson:v1

[..OUTPUT...]
<my-registry>/appregistries/eriknelson@sha256:<digest-blob>
```

Given the fully qualified `CatalogSource` image name we just determined, we're
now able to deploy the image, which will inform OLM of its available packages.
In our case, since we boiled down the entire catalog to just CAM, it should
strictly be the CAM operator. Go ahead and create the following file on disk,
and be sure to replace the image with the fully qualified `CatalogSource` image
notated above.

> NOTE: Because we are deploying CAM, which expects to live in the
`openshift-migration` namespace, now is a good time to create that namespace
with an `oc create ns openshift-migration`.

```yml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: cam-catalog-source
  namespace: openshift-migration
spec:
  sourceType: grpc
  image: <REPLACE_WITH_YOUR_FULL_IMAGE_NAME>
  displayName: CAM Catalog
```

It is, in fact, important that this deployed `CatalogSource` actually be
running in the `openshift-migration` namespace.

You can confirm this has been deployed by checking the pods in the `openshift-migration`
namespace, and can confirm it has been deployed from your internal registryy with a describe:
```
# o get pods -n openshift-migration
NAME                       READY   STATUS    RESTARTS   AGE
cam-catalog-source-nhjhh   1/1     Running   0          3m59s

o describe pod cam-catalog-source-nhjhh
```

Additionally, confirm that OLM has been alerted that your package is now
avialable to the cluster by running the following command, notice it is your
specific catalog that is providing the package:

```
# o get packagemanifests
NAME           CATALOG       AGE
cam-operator   CAM Catalog   7m5s
```

### Installing the cam control cluster

At this point, your operator is now available to be installed with OLM using
the normal procedure via the UI, with the exception that the operator image,
as well as all of our operand images (the various CAM components), will be
actually deployed out of your custom registry rather than pulling from Red Hat's
external registries.

Go ahead and navigate to the OCP console and login, and choose the OperatorHub
section in the left navigation. Be sure to select the `openshift-migration`
namespace rather than the default that is normally selected. You should see cam
as the sole operator available for installation. Go ahead and install the
operator, ensuring it's installed into the `openshift-migration` namespace,
and select the `release-v1.1` release channel. As of this writing, this should
be our latest release: `v1.1.1`.

**TODO: Screenshots**

Dropping back to the command line, you should see a healthy migration operator
running alongside the catalog source pod:

```
# o get pods
NAME                                  READY   STATUS    RESTARTS   AGE
cam-catalog-source-nhjhh              1/1     Running   0          15m
migration-operator-866bb4cb54-dlf92   2/2     Running   0          40s
```

The `ImageContentSourcePolicy` created earlier will ensure that this image was
pulled from the internal registry instead of some external registry.

With a healthy operator ready to deploy the application, you can create the
`MigrationController` object from the OCP UI under installed operators and
accept the default arguments that are presented on the CR.

**TODO: Screenshots**

Again, dropping to the command line, you should see the operator roll out
our various control cluster components, including the controller, the UI, and
velero, all from your personal registry.

```
# o get pods
NAME                                    READY   STATUS    RESTARTS   AGE
cam-catalog-source-nhjhh                1/1     Running   0          21m
migration-controller-6d59b8c4c6-njhlg   2/2     Running   0          41s
migration-operator-866bb4cb54-dlf92     2/2     Running   0          7m23s
migration-ui-5d7998b74f-cqgvx           1/1     Running   0          37s
restic-f527s                            1/1     Running   0          59s
restic-jfx8w                            1/1     Running   0          59s
restic-kcwhn                            1/1     Running   0          59s
velero-5bffbd77c4-j9ndw                 1/1     Running   0          59s
```

Congratulations, you've successfully installed your CAM control cluster, ready
to accept migrated workloads!

## Installing the CAM in the remote cluster (3.11)

The process of installing CAM in a remote cluster, particularly a 3.x cluster,
is somewhat different as the operator is not installed and managed via OLM, and
is instead manually set up via manifest files extracted from our official images.

To deploy the latest v1.1.1 remote cluster cam in disconnected, first extract
the necessary pair of files off of their images: the `operator.yml` file, and the
`controller-3.yml` file. Continuing to work in your chosen directory, run the
following commands on your workstation that has connectivity to Red Hat's
external registry:

```
podman cp $(podman create registry.redhat.io/rhcam-1-1/openshift-migration-rhel7-operator:v1.1):/operator.yml ./
podman $(podman create registry.redhat.io/rhcam-1-1/openshift-migration-rhel7-operator:v1.1):/controller-3.yml ./
```
**TODO: Exactly how too pull images from registry in the control cluster?**

> TODO: To be continued

### TODO:
* Auto storage
* Probably have pre-existing authenticated clients. Need to check that.
* Not sure if the default openshift registry was sufficient. The disconnected
documentation suggests that it is NOT because it does not support pushes by sha
* Everything based on an open, insecure registry in control cluster is questionable.
Need to see how to improve this.
* Follow Jason's blog to get storage setup with caveats
* Fill in links
* Screenshots
