# BuildConfig
oc apply -f bc.yaml
# ConfigMap
oc apply -f config.yaml
# DeploymentConfig
oc process -f dc.yaml --param-file=temp.params -o yaml | oc apply -f -
# Secrets
oc create secret generic gcp-lear-db-sa-secret --from-file=service_account.json=$SA_KEY
