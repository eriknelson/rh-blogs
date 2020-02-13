# Running Cluster Application Migrations in a Disconnected Environment

## Pre-requisites

* podman
* oc client tool > 4.3.1

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

### TODO:
* Probably have pre-existing authenticated clients. Need to check that.
* Not sure if the default openshift registry was sufficient. The disconnected
documentation suggests that it is NOT because it does not support pushes by sha
* Follow Jason's blog to get storage setup with caveats
* Fill in links
* Insecure notes
