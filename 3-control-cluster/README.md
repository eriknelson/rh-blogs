# Using a 3.x Cluster as a CAM Control Cluster

## Pre-requisites

* podman must be installed and working, authenticated to `registry.redhat.io`
* A 3.x cluster containing workloads you're interested in migrating to a 4.x cluster
* Intermediary S3 based storage
* A healthy 4.x cluster ready to accept migrated workloads

## Introduction

As mentioned in my previous disconnected cluster blog, there are a number of
different topologies one can configure CAM depending on what makes sense for
their particular use case. Before starting, I'm going to borrow the cluster
designation definitions from my disconnected blog so we can get a baseline
language established:

> 1) A **control cluster** that contains all CAM components: the controller which
orchestrates migrations and presents the CAM API surface to the cluster that it
has been installed in, the UI from which a user can drive a migration, and the
underlying velero installation that will be used to backup/restore a migrated
application.
>
> 2) A **remote cluster** that runs the underlying velero infrastructure which accepts
instructions from the control cluster to export or import a running workload.
The controller and UI components should be disabled in a remote cluster. One additionally
unique property of a remote cluster is that a "mig" `ServiceAccount` is created
and is granted a `cluster-admin` binding. This `ServiceAccount` token is registered
along with the coordinates to the remote cluster with the control cluster so that
the control cluster's "controller" may interface with the remote cluster's APIs
acting as that `ServiceAccount`.

Under most circumstances, users of CAM will use their 4.x cluster as their
**control cluster**. However, the focus of this blog is to cover using a 3.x
cluster as the CAM control, which is also hosting the application workloads
that you would like to migrate to a 4.x **remote** cluster. There are a few
differences that must be configured to enable this, so let's get started.

## Configuring a 4.x cluster as a remote cluster
Since 4.x clusters ship with OLM installed and have Konveyor (our upstream offering)
automatically made available for installation, we'll use this to set up the 4.x
cluster as a **remote cluster** in this scenario. Additionally, be sure your
cli tools are configured contextually to work with this 4.x cluster.

First, you'll need to create an `openshift-migration` namespace to host our
various components. NOTE: This must be done with either
`oc create ns openshift-migration`, or created via the **namespace** creation
section of the UI. You CANNOT create a project with the prefix "openshift-";
it will be rejected by the project server.

Navigating to the OperatorHub dropdown on the left, be sure to select your
active namespace to be `openshift-migration` and search for Konveyor.

![Konveyor Operator Hub](./KonveyorOperatorHub.png)

For the purposes of this article, we're going to use latest which is the bleeding
edge code out of our master repos, but you also have 1.0 and 1.1 stable branches
available.

Ensure you have selected `openshift-migration` as the namespace to install the
operator inside of, select latest as the package channel, and click subscribe.
You should see an operator pod spin up inside of the namespaces workloads.

### Installing 4.x in "Remote Cluster" mode

Next step is to tell the CAM operator to deploy all of the requisite operands,
which will be different when running in **Remote Cluster** mode. In this case,
we don't need a UI or the controller. Create a `MigrationController` object
to tell the operator you intend for an instance of CAM to be deployed, but by
default you will see the UI and controller both switched on. Set both to false,
and create the `MigrationController`.

```
migration_controller: false
migration_ui: false
```

![MigrationController Creation](./MigrationControllerCreate-4.png)

After waiting a bit, you should see the operator roll out restic pods for each of
your nodes, in addition to Velero. You will also have Velero's API surface now
available for the controller that will live inside your 3.x cluster to communicate
with. NOTE: There is no controller or UI pod present. However, if you run:

`oc get sa -n openshift-migration`, you will see a `mig` sa token that will
be used to connect this cluster as a target cluster to your **control cluster**
(the 3.x cluster), after it has been installed in that cluster.

## Configuring a 3.x cluster as a Control Cluster
Now that we're going to configure the 3.x cluster, reset your oc context to
point to the 3.x cluster. I prefer to keep my kubeconfig files separate, and
switch between the two using the KUBECONFIG environment variable, or keep
two tmux panes open simultaneously configured to each.

Although CAM uses its operator to install and manage the lifecycle of the tool,
OLM is not present by default in a 3.x cluster and must be manually installed
and configured. First, we're going to export the `operator.yml` manifest file, as
well as a default `controller-3.yml` that will be used to tell the operator to
configure the 3.x cluster as a **control cluster** for CAM. Execute the following
commands and be sure to save these files off to a known location:

podman cp $(podman create quay.io/konveyor/mig-operator-container:latest):/operator.yml ./
podman cp $(podman create quay.io/konveyor/mig-operator-container:latest):/controller-3.yml ./


# TODO:
* Consistent branding, use CAM or Konveyor?
