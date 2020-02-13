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

## Installing the CAM in the control cluster (4.3.1)
