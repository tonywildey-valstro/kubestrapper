local kube = import "./bkpr-v1.8.0/manifests/vendor/github.com/bitnami-labs/kube-libsonnet/kube.libsonnet";
local utils = import "./bkpr-v1.8.0/manifests/vendor/github.com/bitnami-labs/kube-libsonnet/utils.libsonnet";
local GRAFANA_DASHBOARDS_CONFIG = "/opt/bitnami/grafana/conf/provisioning/dashboards";

// Cluster-specific configuration
(import "./bkpr-v1.8.0/manifests/platforms/eks.jsonnet") {
	config:: import "kubeprod-autogen.json",
	// Place your overrides here
    // See https://github.com/bitnami/kube-prod-runtime/blob/master/docs/components.md#prometheus

    // prometheus config mod from https://github.com/lensapp/lens/blob/master/troubleshooting/custom-prometheus.md#helm-chart
    // see https://github.com/lensapp/lens/blob/master/jsonnet/custom-prometheus.jsonnet
    prometheus+: {
        retention_days:: 30,
        storage:: 10000,
        config+: {
            global+: {
                scrape_interval_secs: 30,
            },
            scrape_configs_+:: {
                apiservers+: {
                    relabel_configs+: [
                         {
                            action: 'replace',
                            source_labels: ['node'],
                            target_label: 'instance',
                        },
                    ],
                },
                pods+: {
                    relabel_configs+: [
                        {
                            action: 'replace',
                            source_labels: ['__meta_kubernetes_pod_node_name'],
                            target_label: 'kubernetes_node',
                        },
                    ],
                },
            },
        },
    },

    // cognito auth cookies are huge, resulting in nginx 431s
    // see https://stackoverflow.com/questions/59274805/kubernetes-nginx-ingress-request-header-or-cookie-too-large
    // https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#large-client-header-buffers
    nginx_ingress+: {
        config+: {
            data+: {
                "large-client-header-buffers": "8 128k",
                "http2-max-field-size": "128k",  // default: 4k
                "http2-max-header-size": "128k",  
                "client_header_buffer_size": "128k"
            },
        },
    },

    edns+: {
        deploy+: {
            spec+: {
                template+: {
                    spec+: {
                        containers_+: {
                            edns+: {
                                args_+: {
                                    "log-level": "debug",
                                    "policy": "upsert-only",
                                },
                            },
                        },
                    },
                },
            },
        },
    },

    // NGINX dashboards for grafana
    // https://github.com/bitnami/kube-prod-runtime/blob/master/docs/components.md#grafana-dashboards
    // https://github.com/kubernetes/ingress-nginx/blob/master/deploy/grafana/dashboards/nginx.json
    nginx_ingress_dashboards: kube.ConfigMap($.grafana.p + "nginx-ingress-dashboards") + $.grafana.metadata {
        data+: {
            "nginx.json": importstr "./custom/dashboards/nginx.json",
            "nginx_perf.json": importstr "./custom/dashboards/nginx_perf.json",
        },
    },
    grafana+: {
        dashboards_provider+: {
            dashboard_provider+: {
                "nginx_ingress": {
                    folder: "nginx_ingress",
                    type: "file",
                    disableDeletion: false,
                    editable: false,
                    options: {
                        path: utils.path_join(GRAFANA_DASHBOARDS_CONFIG, "nginx_ingress"),
                    },
                },
            },
        },
        grafana+: {
            spec+: {
                template+: {
                    spec+: {
                        volumes_+: {
                            nginx_ingress_dashboards: kube.ConfigMapVolume($.nginx_ingress_dashboards),
                        },
                        containers_+: {
                            grafana+: {
                                volumeMounts_+: {
                                    nginx_ingress_dashboards: {
                                        mountPath: utils.path_join(GRAFANA_DASHBOARDS_CONFIG, "nginx_ingress"),
                                        readOnly: true,
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
}
