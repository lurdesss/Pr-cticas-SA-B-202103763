# Comandos reproducibles — de cero a la plataforma funcionando

Listado compacto, solo comandos, en el orden exacto de ejecución. Para la
explicación de cada paso (y la instalación de las herramientas en
Windows) ver **[../GUIA-WINDOWS.md](../GUIA-WINDOWS.md)**, que es la
misma secuencia con contexto y solución de problemas.

```powershell
# 0. Verificar herramientas
docker --version
minikube version
kubectl version --client
helm version
k6 version

# 1. Cluster
minikube start --cpus=4 --memory=8192 --driver=docker
minikube addons enable ingress
minikube addons enable metrics-server

# 2. Construir las imagenes DENTRO del daemon de Docker de minikube
minikube docker-env | Invoke-Expression

cd P5\services
docker build -t aroma/gateway:1.0.0-dev              .\gateway
docker build -t aroma/catalogo-service:1.0.0-dev      .\catalogo-service
docker build -t aroma/inventario-service:1.0.0-dev    .\inventario-service
docker build -t aroma/pedidos-service:1.0.0-dev       .\pedidos-service
docker build -t aroma/resenas-service:1.0.0-dev       .\resenas-service
cd ..\scripts\cronjob-resumen
docker build -t aroma/cronjob-resumen:1.0.0-dev       .
cd ..\..

# 3. Dependencias de Helm (orden importa: primero cada subchart, luego el padre)
cd charts\sa-platform\charts\gateway;      helm dependency update; cd ..\..\..\..\..
cd charts\sa-platform\charts\catalogo;     helm dependency update; cd ..\..\..\..\..
cd charts\sa-platform\charts\inventario;   helm dependency update; cd ..\..\..\..\..
cd charts\sa-platform\charts\pedidos;      helm dependency update; cd ..\..\..\..\..
cd charts\sa-platform\charts\resenas;      helm dependency update; cd ..\..\..\..\..
cd charts\sa-platform;                     helm dependency update; cd ..\..

# 4. Lint
helm lint charts\sa-platform -f charts\sa-platform\values-dev.yaml

# 5. Namespace + instalacion (version 0.1.0 para demostrar upgrade despues)
helm install sa-platform charts\sa-platform `
  -f charts\sa-platform\values-dev.yaml `
  --namespace sa-p5 --create-namespace

kubectl get pods -n sa-p5 -w
# Ctrl+C cuando todos digan Running/Completed

# 6. Host del Ingress
#    Agregar a C:\Windows\System32\drivers\etc\hosts (como Administrador):
#      127.0.0.1  aroma.local
minikube tunnel   # dejar corriendo en una terminal aparte (Windows)

# 7. Probar
curl.exe http://aroma.local/api/salud
curl.exe -X POST http://aroma.local/api/catalogo/graphql `
  -H "Content-Type: application/json" `
  -d '{"query":"{ productos { id nombre precio } }"}'

# 8. Evidencia: persistencia de datos
kubectl exec -n sa-p5 postgresql-0 -- psql -U aroma -d pedidos_db `
  -c "SELECT COUNT(*) FROM ejecuciones_cron;"
kubectl delete pod -n sa-p5 postgresql-0
kubectl wait -n sa-p5 --for=condition=Ready pod/postgresql-0 --timeout=120s
kubectl exec -n sa-p5 postgresql-0 -- psql -U aroma -d pedidos_db `
  -c "SELECT COUNT(*) FROM ejecuciones_cron;"   # el numero debe seguir ahi o haber crecido

# 9. Evidencia: bloqueo por NetworkPolicy
kubectl run sonda --image=busybox:1.36 -n sa-p5 --rm -it --restart=Never -- `
  wget -qO- --timeout=3 http://catalogo:4001/salud
# debe QUEDARSE COLGADO/fallar por timeout: nadie mas que el gateway puede llamar a catalogo

# 10. Evidencia: flujo asincrono con consumidor caido
kubectl scale deployment/sa-platform-pedidos-worker -n sa-p5 --replicas=0
curl.exe -X POST http://aroma.local/api/pedidos -H "Content-Type: application/json" `
  -d '{"items":[{"productoId":"1","cantidad":1}]}'
kubectl exec -n sa-p5 postgresql-0 -- psql -U aroma -d pedidos_db `
  -c "SELECT COUNT(*) FROM notificaciones_pedidos;"   # no crece: el consumidor esta caido
kubectl scale deployment/sa-platform-pedidos-worker -n sa-p5 --replicas=1
timeout /t 15
kubectl exec -n sa-p5 postgresql-0 -- psql -U aroma -d pedidos_db `
  -c "SELECT COUNT(*) FROM notificaciones_pedidos;"   # ahora si crecio: se proceso sin perdida

# 11. Evidencia: cronjobs
kubectl get cronjob -n sa-p5
kubectl get jobs -n sa-p5 --watch     # esperar a que corran (cada 2 y 10 min)
kubectl exec -n sa-p5 postgresql-0 -- psql -U aroma -d pedidos_db `
  -c "SELECT carne, ejecutado_en AT TIME ZONE 'America/Guatemala' AS hora_gmt6 FROM ejecuciones_cron ORDER BY id DESC LIMIT 5;"
kubectl exec -n sa-p5 postgresql-0 -- psql -U aroma -d pedidos_db `
  -c "SELECT * FROM resumenes_cron ORDER BY id DESC LIMIT 5;"

# 12. Evidencia: helm upgrade + rollback
helm upgrade sa-platform charts\sa-platform `
  -f charts\sa-platform\values-prod.yaml `
  --namespace sa-p5
helm history sa-platform -n sa-p5
helm rollback sa-platform 1 -n sa-p5
helm history sa-platform -n sa-p5

# 13. Evidencia: escalado bajo carga (HPA)
kubectl get hpa -n sa-p5 -w          # terminal A: dejar corriendo
kubectl get pods -n sa-p5 -w         # terminal B: dejar corriendo
k6 run -e BASE_URL=http://aroma.local scripts\carga-k6.js   # terminal C

# 14. Evidencia: actualizacion sin downtime
#    Terminal A: peticiones continuas mientras se actualiza
while ($true) { curl.exe -s -o NUL -w "%{http_code}`n" http://aroma.local/api/salud; Start-Sleep -Milliseconds 500 }
#    Terminal B: forzar un nuevo rollout (por ejemplo, tocando el tag o el ConfigMap)
kubectl rollout restart deployment/sa-platform-gateway -n sa-p5
kubectl rollout status deployment/sa-platform-gateway -n sa-p5
#    En la terminal A no debe aparecer ningun codigo distinto de 200

# 15. Limpieza (si hace falta reiniciar desde cero)
helm uninstall sa-platform -n sa-p5
kubectl delete namespace sa-p5
minikube delete
```
