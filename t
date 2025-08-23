warning: in the working copy of 'k8s/omegaup/base/frontend/ai-editorial-worker.yaml', LF will be replaced by CRLF the next time Git touches it
warning: in the working copy of 'k8s/omegaup/overlays/sandbox/frontend/kustomization.yaml', LF will be replaced by CRLF the next time Git touches it
[1mdiff --git a/k8s/omegaup/base/frontend/ai-editorial-worker.yaml b/k8s/omegaup/base/frontend/ai-editorial-worker.yaml[m
[1mindex a1ac027..917c97d 100644[m
[1m--- a/k8s/omegaup/base/frontend/ai-editorial-worker.yaml[m
[1m+++ b/k8s/omegaup/base/frontend/ai-editorial-worker.yaml[m
[36m@@ -45,7 +45,7 @@[m [mspec:[m
           mountPath: /opt/omegaup[m
         - name: llm-api-secret[m
           mountPath: /home/ubuntu/.my.cnf[m
[31m-          subPath: ai_config[m
[32m+[m[32m          subPath: deepseek[m
       initContainers:[m
       - name: init-volume[m
         image: omegaup/frontend[m
[1mdiff --git a/k8s/omegaup/overlays/sandbox/frontend/kustomization.yaml b/k8s/omegaup/overlays/sandbox/frontend/kustomization.yaml[m
[1mindex 05111c7..774201d 100644[m
[1m--- a/k8s/omegaup/overlays/sandbox/frontend/kustomization.yaml[m
[1m+++ b/k8s/omegaup/overlays/sandbox/frontend/kustomization.yaml[m
[36m@@ -22,9 +22,6 @@[m [msecretGenerator:[m
 - files:[m
   - redis-secret/redis.conf[m
   name: redis-secret[m
[31m-- files:[m
[31m-  - llm-api-secret/ai_config[m
[31m-  name: llm-api-secret[m
 [m
 configMapGenerator:[m
 - behavior: merge[m
[36m@@ -41,6 +38,7 @@[m [mconfigMapGenerator:[m
 resources:[m
 - ../../../base/frontend[m
 - database.yaml[m
[32m+[m[32m- llm-api-secret.yml[m
 [m
             # TODO: Remove once we migrate to jammy.[m
             # TODO: Remove once we migrate to jammy.[m
[1mdiff --git a/k8s/omegaup/overlays/sandbox/frontend/llm-api-secret/ai_config b/k8s/omegaup/overlays/sandbox/frontend/llm-api-secret/ai_config[m
[1mdeleted file mode 100644[m
[1mindex b05dc7d..0000000[m
[1m--- a/k8s/omegaup/overlays/sandbox/frontend/llm-api-secret/ai_config[m
[1m+++ /dev/null[m
[36m@@ -1,5 +0,0 @@[m
[31m-[ai_deepseek][m
[31m-api_key='sandbox-test-deepseek-key'[m
[31m-[m
[31m-[ai_openai][m
[31m-api_key='sandbox-test-openai-key'[m
\ No newline at end of file[m
