# Overview
This is a barebones setup and tear down script for Microsoft Azure.

It performs the following tasks:
- Creates an [Azure Resource Group](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-portal), [Azure Container Registry](https://azure.microsoft.com/en-us/services/container-registry/) (ACR), production and development [Azure Key Vaults](https://azure.microsoft.com/en-us/services/key-vault/) (AKV), and [Azure Kubernetes Service](https://azure.microsoft.com/en-us/services/kubernetes-service/) (AKS) resources.
- Integrates the production AKV with AKS for syncing secrets to Pods using using [Kubernets Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/).
- Applies [`ingress-nginx`](https://kubernetes.github.io/ingress-nginx/), ingress controller configuration, [`cert-manager`](https://cert-manager.io/docs/), SSL/TLS certificate and Azure [Files](https://azure.microsoft.com/en-us/services/storage/files/) and [Disk](https://azure.microsoft.com/en-us/services/storage/disks/) (primarily for a database).
- Offers options to resync AKV keys with AKS, clean the AKS cluster of production resources, and completely delete the Azure Resource Group.

# Disclaimer
**Be mindful of the costs associated with running Azure resources.** 

**Even with a free trial account there are limitations.**

**Please do your due dilligence to understand the associated costs.**

# Initial Setup
You will need to do the following before working with the setup script.

## Prerequisite 
Before clonging the repo, these dependencies need to be setup.

### Azure
You will need an Azure account. There is a [free trial offer](https://azure.microsoft.com/en-us/free/). **Please make sure to review any restrictions or limitations.**

### Azure CLI
After you have an azure account, you need to [install the Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli). Many of the commands the script will run use `az`.

### `zsh`
The scripts are written to be run in a `zsh` shell (macOS default, but has to badded on Linux).

## Cloning the Repo
With the preceeding completed, you can run the following:
```
git clone git@github.com:cheslijones/azure-kubernetes-setup.git
cd azure-kubernetes-setup
```

# Running the Setup Script
The script can be run with the following command:
```
zsh setup.sh
```
Make sure to follow any prompts and read any concluding messages when the script has finished running. 

See the next section for an explanation of each step.

# Walkthrough
The sections below discuss each step for each option as well as default variable setup.

## Default Variables
**This is optional and can be left alone.**

These are just default values if the user decides not to specify them during subsequent steps. The user will be prompted to override them, but simply pressing `enter` will use these values.

The defaults are the following:
```
defaultResourceGroupName='TestAksDeployment'
defaultRegion='westus'
defaultK8sVersion='1.22.6'
defaultNodeSize='Standard_B2s'
defaultNodeCount=1
defaultMaxNodeCount=50
defaultNamespace='prod'
defaultDomain='yourdomain.com'
```
### `defaultResourceGroupName`
The name for the Azure Resource Group. In this script, a lowercase of it is also used as the prefix for resources. 

For example, the Azure Container Registry resource will be name unless the Resource Group Name is overriden:

```
testaksdeploymentacr
```

### `defaultRegion`
The [region](https://azure.microsoft.com/en-us/global-infrastructure/geographies/#overview) to be used when creating resources.

You can find the region names by running:
```
az account list-locations -o table
```
### `defaultK8sVersion`
The Kubernetes version to be used when deploying Azure Kubernetes Service.

You can find the available versions by running (replace `<region>` with your region):
```
az aks get-versions -l <region> -o table 
```

### `defaultNodeSize`
The [Azure Virtual Machine](https://azure.microsoft.com/en-us/pricing/details/virtual-machines/series/) option/size to be used. 

You can find the available VMs in your region by running (replace `<region>` with your region):
```
az vm list-sizes --location <region> -o table
```

### `defaultNodeCount`
How many nodes, VMs, from the previous heading to deploy.

### `defaultMaxNodeCount`
Somewhat confusing, but this *isn't* the maximum number of nodes, VMs, to deploy, but the maximum amount of resources a single Azure Kubernetes Service cluster can run.

### `defaultNamespace`
The namespace used for deploying your production resources to.

### `defaultDomain`
Used in the `ingress-nginx` manifest.

## Option 1: Setup the Resource Group

### Outline
Performs the following operations:
- Prompts and confirms with the user the parameters to use for this option
- Creates the Resource Group using `${resourceGroupName}`
- Creates an ACR resource using `${resourceGroupName:l}acr`
- Creates production and development AKV resources using:
  - `${resourceGroupName:l}akvprod`
  - `${resourceGroupName:l}akvdev`
- Creates an AKV resource using `${resourceGroupName:l}aks`
- Adds the new AKV resource to the `.kubeconfig`
- Creates the production namespace using `${namespace}`

### Next Step
After this option runs, you should add a secret to the production AKV whether through `az cli` or the Azure UI. 

For testing purposes, use the following:

```
Name: TEST-AKV-SECRETS
Value: Hello World
```
After doing so, rerun the script with Option 2.

## Option 2: Integrate AKV and AKS
### Outline
Performs the following operations:
- Prompts and confirms with the user various parameters for this option
- Switches to the correct conext using `{resourceGroupName:l}aks`
- Creates the identity to use with the AKV-AKS integration `az identity create ...`
- Assigns values to about seven variables used in subsequent steps
- Creates a role assignment for the identity using `az role assignment create ...`
- Creates [Pod Identity](https://docs.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access#use-pod-identities) for the identity in AKS using `az aks pod-identity ...`
- Sets AKV secrets permissions for the identity using `az keyvault set-policy ...`
- Applies the `SecretProviderClass` manifest (see the `applySecretProviderClass()` explanation below)
- Applies an `nginx` manifest only used for testing the integration is working

### `applySecretProviderClass()`
It is important to understand a few parts of the `SecretProviderClass` manifest since these will need to be modified depending on your use case.

#### `secretObjects:`
**The `secretObjects` is only required if you intend to use the secret as an environmental variable. It will create a Kubernetes secret (`kubectl create secret ...`). If you do not intend to use AKV secrets as environmental variables, the section can be removed.**
```
...
      secretObjects:
      - secretName: ${1}-prod-secrets
        type: Opaque
        data:
        - objectName: TEST-AKV-SECRETS  #the AKV secret name
          key: TEST_AKV_SECRETS         #the kubectl secret name to use
...
```

New entries will need to be added in the `data:` array for each secret to be created. For example:

```
...
      secretObjects:
      - secretName: ${1}-prod-secrets
        type: Opaque
        data:
        - objectName: TEST-AKV-SECRETS          #the AKV secret name
          key: TEST_AKV_SECRETS                 #the kubectl secret name to use
        - objectName: TEST-AKV-SECRETS-TWO      #corresponds with the AKV secret name
          key: TEST_AKV_SECRETS_TWO             #the kubectl secret name to use
        - objectName: TEST-AKV-SECRETS-THREE    #corresponds with the AKV secret name
          key: TEST_AKV_SECRETS_TWO             #the kubectl secret name to use
...
```
Then in the manifest for the service you would like to deploy, you need to do the following:
```
...
    spec:
      containers:
        - name: api
          image: testaksdeploymentacr.azurecr.io/testaksdeployment-api
          ports:
            - containerPort: 5000
          env:
            - name: TEST_AKV_SECRETS
              valueFrom:
                secretKeyRef:
                  name: testaksdeployment-prod-secrets
                  key: TEST_AKV_SECRETS
            - name: TEST_AKV_SECRETS_TWO
              valueFrom:
                secretKeyRef:
                  name: testaksdeployment-prod-secrets
                  key: TEST_AKV_SECRETS_TWO
            - name: TEST_AKV_THREE
              valueFrom:
                secretKeyRef:
                  name: testaksdeployment-prod-secrets
                  key: TEST_AKV_THREE
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
...
```
**If you do not intend to use as an environmental variable, you do not need to do this. Simply mounting the `secrets-store` makes the secrets available in the Pod file system and the `env:` will not be needed.**

#### `objects` Array
**Every key you want to sync from AKV needs a value in the following section:**
```
...
        objects: |
          array:
            - |
                objectName: TEST-AKV-SECRETS             
                objectType: secret                 
                objectVersion: ""
...
```
For example:
```
...
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
            - |
                objectName: TEST-AKV-SECRETS-THREE             
                objectType: secret                 
                objectVersion: ""
...
```

### Next Step
After the this option has run, you can do the following to test the integration:
- Run the following command:

  ```
  kubectl exec -it nginx -n prod -- cat /mnt/secrets-store/TEST-AKV-SECRETS
  ```
- If `Hello World` in the terminal, then the integration was successful.
- If it did not, it could be the `nginx` Pod is still spinning up which can take about 30 seconds (check with `kubectl get pod nginx -n prod`)
- If there is an error displayed in `kubectl describe pod nginx -n prod`, further investigation is needed--I'd recommend  starting over
- Finally, rerun the script with Option 3 to deploy your production manifests.

## Option 3: Setup Production
### Outline
This section will largely be dependent on your deployment needs. Out-of-the-box, it will do the following barebones deployments:
- Prompts and confirms with the user various parameters for this option
- Switches to the correct conext using `{resourceGroupName:l}aks`
- Installs `ingress-nginx` manifest for Azure
- Installs `cert-manager` 
- Applies the Azure File and Disks permanent volume claim (PVC) manifests
- Applies the `ingress-nginx` manifest
- Applies the TLS/SSL certificate manifest for the domain

### `productionEnv()`
This is the function you need to manually edit to deploy anything else with this option.

### Next Step
- Run `kubectl get ing -n prod` to get the public IP from the `Address` column
- Update your DNS with this IP address
- It can take several minutes for the TLS/SSL certificates to be provisioned and propagate

## Option 4: Resync AKV with AKS
### Outline
This should resync new keys that are added to AKV, and sync them to Pods that are consuming the `secrets-store`. It does the following:
- Prompts and confirms with the user various parameters for this option
- Switches to the correct conext using `{resourceGroupName:l}aks`
- Deletes the current `SecretProviderClass` and `kubectl secrets ...`
- Reapplies the `SecretProviderClass` and creates a new `kubectl secrets ...`

### Next Step
Any Pod that consume the `secrets-store` or `kubectl secrets ...` needs to be reployed for the new secrets to be available.

## Option 5: Reset Azure Kubernetes Service Cluster
### Outline
**This is not reversible.**

Out-of-the-box, it will do the following:
- Prompts and confirms with the user various parameters for this option
- Switches to the correct conext using `{resourceGroupName:l}aks`
- Deletes all resources in the following namespaces: `cert-manager`, `ingress-nginx`, and `${namespace}`
- Creates the namespace `${namespace}` with no resources in it

### Next Step
Rerun options 2 and 3 if needed.

## Option 6: Destory the Azure Resource Group
### Outline
**This is not reversible.**

Simply put: It destroys the Azure Resource Group and purges the Azure Key Vaults. 

It will prompt the user for the Resource Group Name and there will be three confirmations to proceed with destorying the Resource Group: two from this script and one from Azure itself.

### Next Step
None.

# Feedback
Please create an issue to offer feedback, corrections or improvements.