#!/bin/zsh

# Exit when a command fails
set -e

# Default vars can be edited here
defaultResourceGroupName='TestAksDeployment'
defaultRegion='westus'
defaultK8sVersion='1.22.6'
defaultNodeSize='Standard_B2s'
defaultNodeCount=1
defaultMaxNodeCount=50
defaultNamespace='prod'
defaultDomain='yourdomain.com'
defaultEmail='you@yourdomain.com'

# Outline choices and prompt the user
print -P    \\n'%F{cyan}Use the numbers to select one of the following options:'
print       '1. Setup resource group and services (ACR, production and development AKV and and AKS)'
print       '2. Integrate AKV with AKS to sync secrets'
print       '3. Setup Production environment in AKS (ingress-nginx, cert-manager, TLS, Azure File and Disk storage)'
print       '4. Resync AKV with the cluster'
print -P    '5. Clean-up the cluster %F{red}(Deletes ingress-nginx, cert-manager, TLS, Azure and Disk storage)'
print -P    '%F{cyan}6. Destroy the resource group %F{red}(Deletes the resource group and everything in it)%f' \\n
read -k 'userResponse?Enter selection: '

applySecretProviderClass() {

  # Apply the secretProviderClass.yaml
  print -P \\n'%F{green}Applying the secretProviderClass config...%f'
  cat <<EOF | kubectl apply -f -
    apiVersion: secrets-store.csi.x-k8s.io/v1
    kind: SecretProviderClass
    metadata:
      name: aks-akv-secret-provider
      namespace: ${3}
    spec:
      provider: azure
      secretObjects:
      - secretName: ${1}-prod-secrets
        type: Opaque
        data:
        - objectName: TEST-AKV-SECRETS
          key: TEST_AKV_SECRETS
        - objectName: TEST-AKV-SECRETS-TWO
          key: TEST_AKV_SECRETS_TWO
      parameters:
        usePodIdentity: "true"                                        
        keyvaultName: ${1}akvprod
        cloudName: ""                               
        objects: |
          array:
            - |
                objectName: TEST-AKV-SECRETS             
                objectType: secret                 
                objectVersion: ""
            - |
                objectName: TEST-AKV-SECRETS-TWO             
                objectType: secret                 
                objectVersion: ""
        tenantId: ${2}
EOF

}

resourceGroupSetup() {
  print -P \\n\\n"%F{green}Option 1 selected.  Setting up the resource group, ACR, AKV and AKS." \\n

  # Prompt the user for resource group name
  vared -p '%F{cyan}Enter the resource group name (default: %F{magenta}'${defaultResourceGroupName}'%f%F{cyan}):%f ' -c resourceGroupName
  : ${resourceGroupName:=${defaultResourceGroupName}}

  # Prompt the user for region name
  vared -p '%F{cyan}Enter the region (default: %F{magenta}'${defaultRegion}'%f%F{cyan}):%f ' -c region
  : ${region:=${defaultRegion}}

  # Prompt the user for Kubernetes version
  vared -p '%F{cyan}Enter the Kubernetes version (default: %F{magenta}'${defaultK8sVersion}'%f%F{cyan}):%f ' -c k8sVersion
  : ${k8sVersion:=${defaultK8sVersion}}

  # Prompt the user for node size
  vared -p '%F{cyan}Enter the node size (default: %F{magenta}'${defaultNodeSize}'%f%F{cyan}):%f ' -c nodeSize
  : ${nodeSize:=${defaultNodeSize}}

  # Prompt the user for node count
  vared -p '%F{cyan}Enter the node count (default: %F{magenta}'${defaultNodeCount}'%f%F{cyan}):%f ' -c nodeCount
  : ${nodeCount:=${defaultNodeCount}}

  # Prompt the user for maximum node count 
  vared -p '%F{cyan}Enter the maximum node count (default: %F{magenta}'${defaultMaxNodeCount}'%f%F{cyan}):%f ' -c maxNodeCount
  : ${maxNodeCount:=${defaultMaxNodeCount}}

  # Prompt the user for maximum node count 
  vared -p '%F{cyan}Enter the production namespace to use (default: %F{magenta}'${defaultNamespace}'%f%F{cyan}):%f ' -c namespace
  : ${namespace:=${defaultNamespace}}

  # Confirm entries
  print -P  \\n'%F{cyan}Confirm the following parameters: '
  print -P  '  \- Resource Group:%f' ${resourceGroupName}
  print -P  '  %F{cyan}\- Region:%f' ${region}
  print -P  '  %F{cyan}\- Kubernetes Version:%f' ${k8sVersion}
  print -P  '  %F{cyan}\- Node Size:%f' ${nodeSize}
  print -P  '  %F{cyan}\- Node Count:%f' ${nodeCount}
  print -P  '  %F{cyan}\- Max Node Count:%f' ${maxNodeCount}
  print -P  '  %F{cyan}\- Namespace:%f' ${namespace} \\n

  
  # If the user confirms, continue with creating the resources group and resources
  if read -q 'userConfirmation?Parameters correct? (y/n): '; then
    
    # Create the resource group
    print -P \\n\\n'%F{green}Creating the '${resourceGroupName}' resource group...%f'
    az group create -l ${region} -n ${resourceGroupName}

    # Create ACR resource
    print -P \\n'%F{green}Creating the '${resourceGroupName:l}'acr container registry...%f'
    az acr create -g ${resourceGroupName} -n ${resourceGroupName:l}acr --sku Basic -l ${region}

    # Create AKV production and development resources
    print -P \\n'%F{green}Creating the '${resourceGroupName:l}'akvdev key vault...%f'
    az keyvault create -n ${resourceGroupName:l}akvdev -g ${resourceGroupName} -l ${region}
    print -P \\n'%F{green}Creating the '${resourceGroupName:l}'akvprod key vault...%f'
    az keyvault create -n ${resourceGroupName:l}akvprod -g ${resourceGroupName} -l ${region}

    # Create AKS resrouce
    print -P \\n'%F{green}Creating the '${resourceGroupName:l}'aks cluster... This can take about 10 minutes...%f'
    az aks create -n ${resourceGroupName:l}aks \
      -g ${resourceGroupName} \
      --kubernetes-version=$k8sVersion \
      --node-count ${nodeCount} \
      -l ${region} \
      --enable-pod-identity \
      --attach-acr ${resourceGroupName:l}acr \
      -s ${nodeSize} \
      --network-plugin azure \
      -m ${maxNodeCount} \
      --enable-addons azure-keyvault-secrets-provider

    # Add the AKS context
    print -P \\n'%F{green}Adding the '${resourceGroupName:l}'aks context...%f'
    az aks get-credentials -n ${resourceGroupName:l}aks -g $resourceGroupName

    # Create prod namespace
    print -P \\n'%F{green}Creating the '${namespace}' namespace...%f'
    kubectl create ns ${namespace}

  fi

  print -P \\n'%F{green}Done creating the resource group and all services.'

  print -P \\n'You should do the following next:'
  print '  \- Add secrets to the Azure Key Vaults'
  print -P '  \- Rerun this script and use option 2 to integrate the production AKV and AKS%f'
}

akvIntegration() {
  print -P \\n\\n"%F{green}Option 2 selected.  Integrating AKV and AKS using CSI." \\n

  # Prompt the user for the resource group and integration identity name
  vared -p '%F{cyan}Enter the resource group name (default: %F{magenta}'${defaultResourceGroupName}'%f%F{cyan}):%f ' -c resourceGroupName
  : ${resourceGroupName:=${defaultResourceGroupName}}

  # Prompt the user for maximum node count 
  vared -p '%F{cyan}Enter the production namespace to use (default: %F{magenta}'${defaultNamespace}'%f%F{cyan}):%f ' -c namespace
  : ${namespace:=${defaultNamespace}}

  # Confirm entries
  print -P  \\n'%F{cyan}Confirm the following parameters: '
  print -P  '  \- Resource Group:%f' ${resourceGroupName}
  print -P  '  %F{cyan}\- Namespace:%f' ${namespace} \\n

  # If the user confirms the resource group name, continue with the process
  if read -q 'userConfirmation?Parameters correct? (y/n): '; then

    # Set the correct context
    print -P \\n\\n'%F{green}Switching to the '${resourceGroupName:l}'akv context...%f'
    kubectl config use-context ${resourceGroupName:l}aks

    # Create identity for the integration
    print -P \\n'%F{green}Creating the AksAkvIntegrationIdentity} integration identity...%f'
    az identity create -g ${resourceGroupName} -n AksAkvIntegrationIdentity

    # Create ACR resource
    print -P \\n'%F{green}Setting variables for next steps...%f'
    subscriptionId=$(az account show --query id -otsv)
    print 'subscriptionId: '${subscriptionId} \\n

    aksClientId=$(az aks show -n ${resourceGroupName:l}aks -g ${resourceGroupName} --query identityProfile.kubeletidentity.clientId -otsv)
    print 'aksClientId: '${aksClientId} \\n

    aksResourceGroup=$(az aks show -n ${resourceGroupName:l}aks -g ${resourceGroupName} --query nodeResourceGroup -otsv)
    print 'aksResourceGroup: '${aksResourceGroup} \\n

    aksResourceId=$(az group show -n ${aksResourceGroup} -o tsv --query "id")
    print 'aksResourceId: '${aksResourceId} \\n

    scope="/subscriptions/${subscriptionId}/resourcegroups/${aksResourceGroup}"
    print 'scope: '${scope} \\n

    tenantId=$(az account show --query tenantId -otsv)
    print 'tenandtId: '${tenantId} \\n

    identityClientId=$(az identity show -g ${resourceGroupName} -n AksAkvIntegrationIdentity --query clientId -otsv)
    print 'identityClientId: '${identityClientId} \\n

    identityResourceId=$(az identity show -g ${resourceGroupName} -n AksAkvIntegrationIdentity --query id -otsv)
    print 'identityResourceId: '${identityResourceId}

    # Create roles necessary for the integration
    print -P \\n'%F{green}Creating the necessary role permissions...%f'
    az role assignment create --role "Virtual Machine Contributor" --assignee ${identityClientId} --scope ${aksResourceId}

    # Create pod identity for the integration
    print -P \\n'%F{green}Creating the pod identity for integration...%f'
    az aks pod-identity add -g ${resourceGroupName} --cluster-name ${resourceGroupName:l}aks --namespace prod --name aks-akv-identity --identity-resource-id ${identityResourceId}

    # Set the GET policy for the secrets for the identity
    print -P \\n'%F{green}Setting the integration permissions for the production AKV...%f'
    az keyvault set-policy -n ${resourceGroupName:l}akvprod --secret-permissions get --spn ${identityClientId}

    # Call the applySecretProviderClass function
    applySecretProviderClass ${resourceGroupName:l} ${tenantId} ${namespace}

    # Apply the pod config to integration
    print -P \\n'%F{green}Applying the pod config to test integration...%f'
    cat <<EOF | kubectl apply -f -
      kind: Pod
      apiVersion: v1
      metadata:
        name: nginx
        namespace: ${namespace}
        labels:
          aadpodidbinding: aks-akv-identity
      spec:
        containers:
          - name: nginx
            image: nginx
            volumeMounts:
            - name: secrets-store01-inline
              mountPath: /mnt/secrets-store
              readOnly: true
        volumes:
          - name: secrets-store01-inline
            csi:
              driver: secrets-store.csi.k8s.io
              readOnly: true
              volumeAttributes:
                secretProviderClass: aks-akv-secret-provider
EOF

  fi

  print -P \\n'%F{green}Done with the AKS and AKV integration.'

  print -P \\n'You should do the following next:'
  print -P '  %F{green}\- Run: %F{magenta}kubectl exec -it nginx -n prod -- cat /mnt/secrets-store/TEST-AKV-SECRETS'
  print -P '  %F{green}\- You should see "Hello World" print out on the console, which means the integration was successful'
  print -P '  %F{green}\- You can then delete that pod with: %F{magenta}kubectl delete pod nginx -n prod'
  print -P '  %F{green}\- Lastly, rerun this script and select option 3 to setup the production environment%f'

}

productionEnv() {
  print -P \\n\\n"%F{green}Option 3 selected. Deploying ingress-nginx, cert-manager, ingress controller, Azure storage, and SSL/TLS." \\n

  # Prompt the user for the resource group and integration identity name
  vared -p '%F{cyan}Enter the resource group name (default: %F{magenta}'${defaultResourceGroupName}'%f%F{cyan}):%f ' -c resourceGroupName
  : ${resourceGroupName:=${defaultResourceGroupName}}

  # Prompt the user for maximum node count 
  vared -p '%F{cyan}Enter the production namespace to use (default: %F{magenta}'${defaultNamespace}'%f%F{cyan}):%f ' -c namespace
  : ${namespace:=${defaultNamespace}}

  # Prompt the user for the resource group and integration identity name
  vared -p '%F{cyan}Enter the domain name (default: %F{magenta}'${defaultDomain}'%f%F{cyan}):%f ' -c domain
  : ${domain:=${defaultDomain}}

  # Prompt the user for the resource group and integration identity name
  vared -p '%F{cyan}Enter your email (default: %F{magenta}'${defaultEmail}'%f%F{cyan}):%f ' -c email
  : ${email:=${defaultEmail}}


  # Confirm entries
  print -P  \\n'%F{cyan}Confirm the following parameters: '
  print -P  '  \- Resource Group:%f' ${resourceGroupName}
  print -P  '  %F{cyan}\- Namespace:%f' ${namespace}
  print -P  '  %F{cyan}\- Domain name:%f' ${domain}
  print -P  '  %F{cyan}\- Email:%f' ${email} \\n

  # If the user confirms the resource group name, continue with the process
  if read -q 'userConfirmation?Parameters correct? (y/n): '; then

    # Set the correct context
    print -P \\n\\n'%F{green}Switching to the '${resourceGroupName:l}'akv context...%f'
    kubectl config use-context ${resourceGroupName:l}aks

    # Installing ingress-nginx into the cluster
    print -P \\n'%F{green}Installing ingress-nginx into the cluster...%f'
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.1/deploy/static/provider/cloud/deploy.yaml

    # Install cert-manager into the cluster
    print -P \\n'%F{green}Installing cert-manager into the cluster...%f'
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.7.1/cert-manager.yaml

    # Apply Azure Storage configuration
    print -P \\n'%F{green}Applying Azure Storage configuration...%f'
    cat <<EOF | kubectl apply -f -
      apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: file-storage
        namespace: ${namespace}
      spec:
        accessModes:
          - ReadWriteMany
        storageClassName: azurefile
        resources:
          requests:
            storage: 1Gi
EOF
    cat <<EOF | kubectl apply -f -
      apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: disk-storage
        namespace: ${namespace}
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: default
        resources:
          requests:
            storage: 1Gi
EOF

    # Apply ingress-nginx configuration
    print -P \\n'%F{green}Applying ingress-nginx configuration...%f'
    cat <<EOF | kubectl apply -f -
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        annotations:
          kubernetes.io/ingress.class: 'nginx'
          cert-manager.io/cluster-issuer: 'letsencrypt-prod'
        name: ingress-prod
        namespace: ${namespace}
      spec:
        tls:
          - hosts:
              - ${domain}
              - www.${domain}
            secretName: tls-prod
        rules:
          - host: ${domain}
            http:
              paths:
                - path: /
                  pathType: Prefix
                  backend:
                    service:
                      name: client-cluster-ip-service-prod
                      port:
                        number: 3000
          - host: www.${domain}
            http:
              paths:
                - path: /
                  pathType: Prefix
                  backend:
                    service:
                      name: client-cluster-ip-service-prod
                      port:
                        number: 3000
EOF

    # Apply certificate configuration
    print -P \\n'%F{green}Applying certificate configuration...%f'
    cat <<EOF | kubectl apply -f -
      apiVersion: cert-manager.io/v1
      kind: ClusterIssuer
      metadata:
        name: letsencrypt-prod
        namespace: cert-manager
      spec:
        acme:
          server: https://acme-v02.api.letsencrypt.org/directory
          email: ${email}
          privateKeySecretRef:
            name: letsencrypt-prod
          solvers:
            - http01:
                ingress:
                  class: nginx
EOF

  fi

  print -P \\n'%F{green}Done setting up the production environment.'

  print -P \\n'You should do the following next:'
  print -P '  %F{green}\- Get the deployment public IP with: %F{magenta}kubectl get ing -n prod'
  print -P '  %F{green}\- Update DNS records to use the IP address%f'

}

resyncAKV() {

  print -P \\n\\n"%F{green}Option 4 selected. Resyncing AKV." \\n

  # Prompt the user for the resource group and integration identity name
  vared -p '%F{cyan}Enter the resource group name (default: %F{magenta}'${defaultResourceGroupName}'%f%F{cyan}):%f ' -c resourceGroupName
  : ${resourceGroupName:=${defaultResourceGroupName}}

  # Prompt the user for maximum node count 
  vared -p '%F{cyan}Enter the production namespace to use (default: %F{magenta}'${defaultNamespace}'%f%F{cyan}):%f ' -c namespace
  : ${namespace:=${defaultNamespace}}

  # Confirm entries
  print -P  \\n'%F{cyan}Confirm the following parameters: '
  print -P  '  \- Resource Group:%f' ${resourceGroupName}
  print -P  '  %F{cyan}\- Namespace:%f' ${namespace} \\n

  # If the user confirms the resource group name, continue with the process
  if read -q 'userConfirmation?Parameters correct? (y/n): '; then

    # Set the correct context
    print -P \\n\\n'%F{green}Switching to the '${resourceGroupName:l}'akv context...%f'
    kubectl config use-context ${resourceGroupName:l}aks

    # Getting the tenantId
    print -P \\n'%F{green}Getting the Tenant ID...%f'
    tenantId=$(az account show --query tenantId -otsv)
    print 'tenandtId: '${tenantId}
  
    # Delete the service and secrets before reapplying
    print -P \\n'%F{green}Deleting the existing SecretProvierClass and Secrets...%f'
    kubectl delete secrets ${resourceGroupName:l}-prod-secrets -n ${namespace}    

    # Call the applySecretProviderClass function
    applySecretProviderClass ${resourceGroupName:l} ${tenantId} ${namespace}
  fi

  print -P \\n'%F{green}Done resyncing AKV.'

}

cleanCluster() {
  print -P \\n\\n"%F{red}Option 5 selected. Cleaning the cluster will remove: ingress-nginx, storage, and TLS/SSL.%f" \\n
  
  # Prompt the user for the resource group
  vared -p '%F{cyan}Enter the resource group name (default: %F{magenta}'${defaultResourceGroupName}'%f%F{cyan}):%f ' -c resourceGroupName
  : ${resourceGroupName:=${defaultResourceGroupName}}

  # Prompt the user for maximum node count 
  vared -p '%F{cyan}Enter the production namespace to use (default: %F{magenta}'${defaultNamespace}'%f%F{cyan}):%f ' -c namespace
  : ${namespace:=${defaultNamespace}}

  # Confirm entries
  print -P  \\n'%F{cyan}Confirm the following parameters: '
  print -P  '  \- Resource Group:%f' ${resourceGroupName}
  print -P  '  %F{cyan}\- Namespace:%f' ${namespace} \\n
  
  # If the user confirms the resource group name, continue with the process
  if read -q 'userConfirmation?Parameters correct? (y/n): '; then

    # Confirm again the user wants to destroy this resource group
    print -P \\n\\n'%F{red}This is destructive and will restore the cluster to its initial state.%f' \\n
    
    # If the user confirms destroying it, continue with the process
    if read -q 'confirmReset?Continue with reset? (y/n): '; then

      # Set the correct context
      print -P \\n\\n'%F{green}Switching to the '${resourceGroupName:l}'akv context...%f'
      kubectl config use-context ${resourceGroupName:l}aks

      # Delete PostgreSQL configuration
      print -P \\n'%F{green}Deleting the namespace '${namespace}'...%f'
      kubectl delete all --all -n ingress-nginx
      kubectl delete all --all -n cert-manager
      kubectl delete all --all -n ${namespace}
      kubectl create ns ${namespace}
    fi
  fi

  # Indicate to the user the process has finished
  print -P \\n'%F{red}Finished cleaning up the cluster.%f'

}

destoryResourceGroup() {
  print -P \\n\\n"%F{red}Option 6 selected.  Destroying the resource group.%f" \\n
  
  # Prompt the user for the resource group
  vared -p '%F{cyan}Enter the resource group name (default: %F{magenta}'${defaultResourceGroupName}'%f%F{cyan}):%f ' -c resourceGroupName
  : ${resourceGroupName:=${defaultResourceGroupName}}

  # Confirm entries
  print -P  \\n'%F{cyan}Confirm the following parameters: '
  print -P  '  \- Resource Group:%f' ${resourceGroupName} \\n
  
  # If the user confirms the resource group name, continue with the process
  if read -q 'userConfirmation?Resource name correct? (y/n): '; then
    
    # Confirm again the user wants to destroy this resource group
    print -P \\n\\n'%F{red}This is destructive and will get rid of everything in the resource group '${resourceGroupName}'.%f' \\n
    
    # If the user confirms destroying it, continue with the process
    if read -q 'confirmDestroy?Destroy resource group? (y/n): '; then
      print -P \\n\\n'%F{red}Destroying the resource group '${resourceGroupName}'... This can take about 10 minutes...%f' \\n
      az group delete -n ${resourceGroupName}

      print -P \\n'%F{red}Purge the '${resourceGroupName:l}'akvprod and '${resourceGroupName:l}'akvdev key vaults...%f'
      az keyvault purge --name ${resourceGroupName:l}akvprod
      az keyvault purge --name ${resourceGroupName:l}akvdev
    fi
  fi

  # Indicate to the user the process has finished
  print -P \\n'%F{red}Finished destroying resource group '${resourceGroupName}'.%f'

}

# Based on the user's input do the following
case $userResponse in
[1])
  # If 1, setup the resource group
  resourceGroupSetup
  ;;
[2])
  # If 2, integrate AKV and AKS 
  akvIntegration
  ;;
[3])
  # If 3, apply production manifests
  productionEnv
  ;;
[4])
  # If 4, apply production manifests
  resyncAKV
  ;;
[5])
  # If 5, delete production manifests
  cleanCluster
  ;;
[6])
  # If 6, destory the resource group
  destoryResourceGroup
  ;;
*)
  # Anyting else, invalid selection response
  print -P \\n\\n'%F{red}"'${userResponse}'" is not a valid option. Exiting script.%f'
  ;;
esac