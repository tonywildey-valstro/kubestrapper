# commands

## create a cluster

```
make ENVIRONMENT=production CLUSTER_NAME=botany-production cluster-create
```

## delete a cluster

```
make ENVIRONMENT=staging cluster-delete
```

## deploy kubeprod runtime

```
make ENVIRONMENT=dev CLUSTER_NAME=dev DNS_ZONE=dev.botany.io runtime-deploy
```

## update kubeprod runtime

```
make ENVIRONMENT=staging CLUSTER_NAME=botany-staging DNS_ZONE=staging.botany.io runtime-deploy
```


## Scaling nodegroups

```
eksctl scale nodegroup --cluster=botany-production --nodes=4 --name=nodes
```