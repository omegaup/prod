# Releasing a new runner image

```shell
TF_VAR_az_runner_image=true terraform plan -out=tfplan
terraform apply tfplan
while true; do
  vm_state="$(az vm show --resource-group omegaup-runner-image-builder --name omegaup-runner-image-builder --show-details | jq -r '.powerState')"
  if [[ "${vm_state}" != "VM running" ]]; then
    break
  fi
  echo "${vm_state}"
  sleep 10
done
az vm generalize --resource-group omegaup-runner-image-builder --name omegaup-runner-image-builder
az image create --resource-group omegaup-runner-image-builder --source omegaup-runner-image-builder --name omegaup-runner-image-20211231
```

And then create a new version at https://portal.azure.com/#@omegauporg.onmicrosoft.com/resource/subscriptions/9fc6c11d-9406-42f8-9a78-3813ed0875fa/resourceGroups/omegaup-runner-image-builder/providers/Microsoft.Compute/galleries/omegaup_runner/images/omegaup-runner-image-20211231/overview
