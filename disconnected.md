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
oc tooling (featurem missing), and the --manifest-dir argument doesn't work with
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

### TODO:
* Probably have pre-existing authenticated clients. Need to check that.
* Not sure if the default openshift registry was sufficient. The disconnected
documentation suggests that it is NOT because it does not support pushes by sha
* Follow Jason's blog to get storage setup with caveats
* Fill in links
* Insecure notes
