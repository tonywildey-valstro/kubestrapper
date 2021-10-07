# NOTES

* some things in makefile and `kubeprod-manifest` are currently EKS-specific
* need to make sure you set the env vars listed in the [kubeprod docs](https://github.com/bitnami/kube-prod-runtime/blob/master/docs/quickstart-eks.md#step-1-set-up-the-cluster) before you run `make runtime-deploy`
* also could try the "generic cluster" setup from the kubeprod docs

# commands

## create a cluster

```
make ENVIRONMENT=production CLUSTER_NAME=andy-production cluster-create
```

## delete a cluster

```
make ENVIRONMENT=staging cluster-delete
```

## deploy kubeprod runtime

```
make ENVIRONMENT=dev CLUSTER_NAME=dev DNS_ZONE=dev.andy.io runtime-deploy
```

## update kubeprod runtime

```
make ENVIRONMENT=staging CLUSTER_NAME=botany-staging DNS_ZONE=staging.andy.io runtime-deploy
```


## Scaling nodegroups

```
eksctl scale nodegroup --cluster=andy-production --nodes=4 --name=nodes
```
