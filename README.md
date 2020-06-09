# Wave infrastructure Installation

Installing and configuring all prerequisites for Wave product by Spot.  

 - **Spark Operator** 

The [Spark Operator](https://github.com/GoogleCloudPlatform/spark-on-k8s-operator) project originated from Google Cloud Platform team.  It implements the operator pattern that encapsulates the domain knowledge of running and managing Spark applications in custom resources and defines custom controllers that operate on those custom resources. 

The Operator defines two Custom Resource Definitions (CRDs), SparkApplication and ScheduledSparkApplication. These CRDs are abstractions of the Spark jobs and make them native citizens in Kubernetes. From here, you can interact with submitted Spark jobs using standard Kubernetes tooling such as kubectl via custom resource objects representing the jobs.

 - **Spark History Server** 

[Spark History Server](https://spark.apache.org/docs/latest/monitoring.html#viewing-after-the-fact) provides a web UI for completed and running Spark applications. The supported storage backends are HDFS, Google Cloud Storage (GCS), Azure Blob Storage (WASBS) and PersistentVolumeClaim (PVC). The current installation allows you to mount EFS storage as PersistentVolumes.

 - **EFS-Provisioner** 

[EFS-provisioner](https://github.com/kubernetes-incubator/external-storage/tree/master/aws/efs) allows you to mount EFS storage as PersistentVolumes in Kubernetes. It consists of a container that has access to an AWS EFS resource. The container reads a configmap which contains the EFS filesystem ID, the AWS region and the name you want to use for your efs-provisioner. This name will be used later when you create a storage class."

This script deploys the EFS Provisioner, a StorageClass for EFS volumes and a PersistentVolumeClaim.

The EFS external storage provisioner runs in a Kubernetes cluster and will create persistent volumes in response to the PersistentVolumeClaim resources being created. These persistent volumes will be mounted on containers. 

# Prerequisites

 - The **Spark Operator** requires Kubernetes version 1.13 or above to use the subresource support for CustomResourceDefinitions, which became beta in 1.13 and is enabled by default in 1.13 and higher.
 - The **EFS-provisioner** requires the EFS file system and endpoints. (https://docs.aws.amazon.com/efs/latest/ug/creating-using-create-fs.html). The endpoints must be accessible to the cluster and the cluster nodes must have permission to mount EFS file systems.

> The script will automatically create necessarry **Namespaces**:
>  - wave-sparkoperator
>  - wave-applications

# Installing

To install all needed infrastructure you have to run the script:
   
     wave-infra-installation.sh

To check expected args use *`--help`* argument:

     wave-infra-installation.sh --help

Example:

    wave-infra-installation.sh --efs-enabled true --efs-file-system-id [EFS ID] --efs-aws-region [AWS Region] --pvc-enabled true

In this case will be installed the Spark Operator, Spark History, efs-provisioner, PVC.

# Parameters

|Parameter  | Description | Default|
|--|--|--|
| *`efs-enabled`* 		    |Allows to mount EFS storage  					                                                      | *`false`* |
|`*efs-file-system-id`*	|**Mondatory** if *`efs-enabled`* is *`true`*                                            | *`Empty`*	|
|*`efs-aws-region`*		   |**Mondatory** if *`efs-enabled`* is *`true`*	                                           | *`Empty`*	|
|*`pvc-enabled`*		      |Allows to create PVC. Will be *`true`* when *`efs-enabled`* is *`true`*                 | *`false`*|
|*`dry-run`*			         |Allows you inspect and test the installation process, but not actually install anything | *`false`*|
|*`uninstall`*			       |Delete all deployments/configs installed by Wave                                        | *`false`* |

# Uninstallig

To delete all components installed by Wave run the following command:

    wave-infra-installation.sh --uninstall

If you installed the PVC (*`efs-enabled`* and *`pvc-enabled`* are  *`true`*) and you want it uninstalled automatically you should set the *`--pvc-enabled true`*  argument:

    wave-infra-installation.sh --uninstall --pvc-enabled true
 
