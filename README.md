# Arquitectura Elástica y Alta Disponibilidad en GCP con Terraform

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![GCP](https://img.shields.io/badge/Google_Cloud-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![IaC](https://img.shields.io/badge/IaC-2e7d32?style=for-the-badge&logo=files&logoColor=white)

## Resumen del proyecto
Arquitectura elástica y de alta disponibilidad desplegada en Google Cloud Platform mediante Terraform. El objetivo principal fue diseñar una plataforma resiliente capaz de escalar automáticamente (*scale-out*) ante picos de demanda y regresar a un estado de bajo costo (*scale-in*) cuando la carga disminuye.

**Características Principales:**
- **Red y acceso administrativo:** instancias sin IP pública, acceso mediante IAP y salida a internet a través de Cloud NAT.
- **Cómputo Regional:** grupo regional de instancias administradas (MIG), distribuido entre múltiples zonas y configurado con autohealing.
- **Autoscaling:** escalado automático basado en la utilización de CPU.
- **Balanceo:** External Managed Application Load Balancer (Proxy Envoy).

**Resultados Obtenidos:**
- Escalado horizontal validado mediante pruebas controladas de CPU.
- Distribución multizona de las instancias administradas por el MIG.
- Ciclo completo de creación, validación y destrucción de la infraestructura ejecutado correctamente mediante Terraform.

*Durante el desarrollo del laboratorio se registraron incidentes reales relacionados con el comportamiento del autoscaler, la configuración de red, los startup scripts y las dependencias entre recursos durante la destrucción. Sus causas y soluciones se detallan en la sección de troubleshooting.*

### Aviso importante
Este proyecto corresponde a la fase 1 (stateless) de una arquitectura de laboratorio. El diseño se concentra en analizar el cómputo elástico y el comportamiento de la red, sin desplegar una capa de datos persistente. Cloud SQL aparece en el diagrama como el componente de persistencia planificado para la fase 2.

## Índice
1. [Diagrama de arquitectura visual](#diagrama-de-arquitectura-visual)
2. [Stack tecnologico](#stack-tecnologico)
3. [Requisitos](#requisitos)
4. [Despliegue](#despliegue)
5. [Comportamiento Esperado del Sistema](#comportamiento-esperado-del-sistema)
6. [Operaciones](#operaciones)
7. [Ciclo de vida de las VMs](#ciclo-de-vida-de-las-vms)
8. [Destrucción de la infraestructura](#destrucción-de-la-infraestructura)
9. [Notas de Diseño](#notas-de-diseño)
10. [FinOps y Análisis de Costos (Estimación Mensual)](#finops-y-análisis-de-costos-estimación-mensual)
11. [Registro de Incidentes y Resolución de Problemas](#registro-de-incidentes-y-resolución-de-problemas)
12. [Colofón el por que de itaca Itaca](#colofon-el-por-que-de-itaca-itaca)
13. [Contacto](#contacto)

## Diagrama de arquitectura visual.
<p align="center">
  <img src="Imagenes/Diagrama.png" alt="Arquitectura fase 1 y fase 2" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Arquitectura stateless — Fase 1. El componente Cloud SQL representa la capa de persistencia planificada para la Fase 2."</em>
</p>

## Stack tecnologico.
- Infraestructura como Código: Terraform
- Proveedor Cloud: Google Cloud Platform (GCP)
- Cómputo Elástico: Compute Engine (e2-micro), Regional Managed Instance Group (MIG)
- Balanceo de Carga: Application Load Balancer (External Managed)
- Redes: Custom VPC, Cloud NAT, Cloud Router, Proxy Subnet
- Acceso Administrativo: Identity-Aware Proxy (IAP)
- Capa de Aplicación: Debian 11, Bash (Startup Scripts), Python 3, FastAPI, Uvicorn, Stress

## Requisitos.
- **cuenta de Google Cloud Computing GCP** - un proyecto de GCP creado y activo, cuenta de facturacion (Billing) vinculada al proyecto.
- **APIs Habilitadas** - la api de compute engine habilitada en el proyecto.
- **Herramientas de línea de comandos (CLI) y terraform** - terraform instalado en tu entorno local, Gcloud instalado y autenticado.
- **Permisos de IAM** - tener los permisos en GCP para crear redes y máquinas virtuales.

## Notas de diseño

* **Arquitectura stateless — Fase 1:** esta primera versión fue diseñada intencionalmente sin una capa de persistencia para concentrar la validación en el cómputo elástico y la distribución de red. La base de datos se incorporará en la fase 2.

* **Recursos explícitos frente a módulos:** se utilizaron recursos individuales de Terraform en lugar de módulos prefabricados para conservar control granular sobre la configuración. De esta manera, cada bloque representa explícitamente un componente de la topología y facilita comprender sus dependencias.

* **Acceso administrativo mediante IAP:** las instancias no poseen IP pública y el puerto `22` no está expuesto a internet. La regla `allow-ssh-itaca` acepta conexiones únicamente desde `35.235.240.0/20`, rango utilizado por Identity-Aware Proxy, evitando la necesidad de un bastion host.

* **Topología de red privada:** la VPC utiliza `auto_create_subnetworks = false` para controlar explícitamente el direccionamiento y evitar solapamientos. Cloud NAT y Cloud Router permiten que las VMs descarguen paquetes sin asignarles direcciones públicas.

* **Alta disponibilidad multizona:** el MIG es regional y distribuye instancias entre `southamerica-west1-a` y `southamerica-west1-b`. Esto permite recrear capacidad en otra zona ante una falla; para mantener servicio inmediato durante una caída zonal deben existir al menos dos réplicas saludables.

* **Balanceador regional y proxy-only subnet:** el Application Load Balancer `EXTERNAL_MANAGED` requiere una subred dedicada. `itaca_proxy`, configurada con el propósito `REGIONAL_MANAGED_PROXY`, separa el tráfico de los proxies Envoy del tráfico interno de las VMs.

* **Instancias reemplazables mediante startup scripts:** cada VM parte de una imagen limpia de Debian 11 y ejecuta el mismo script inyectado como metadata para instalar FastAPI, Uvicorn y sus dependencias. Esto permite recrear o rotar nodos manteniendo una configuración reproducible.

* **Estabilidad de métricas y prevención de flapping:** la instalación de dependencias puede saturar temporalmente las máquinas `e2-micro`, provocando que el autoscaler interprete el arranque como carga real. Para separar ambos eventos, `initial_delay_sec = 300` protege el autohealing durante la inicialización, `cooldown_period = 180` define cuándo las métricas resultan representativas y `sleep 300` retrasa la prueba de estrés hasta que la aplicación se estabiliza.


## Despliegue.
- **ADVERTENCIA** El archivo variables.tf permite configurar el proyecto, la región, el tipo de máquina y las cantidades mínima y máxima de réplicas. Sus valores predeterminados corresponden al escenario utilizado para validar el laboratorio y permiten desplegarlo sin introducir cada valor manualmente. La arquitectura utiliza recursos específicos de Google Cloud y no puede migrarse a otro proveedor modificando únicamente providers.tf.
1. Clonar el repositorio: git clone https://github.com/Ulises-Acuna-Bianchi/Arquitectura-Elastica-y-Alta-Disponibilidad-en-GCP-con-Terraform.
2. Entrar en el directorio del proyecto: cd Arquitectura-Elastica-y-Alta-Disponibilidad-en-GCP-con-Terraform
3. Configurar las credenciales predeterminadas de aplicación de Google Cloud: gcloud auth application-default login
4. Inicializar Terraform y descargar el provider requerido: terraform init
5. Revisar el plan de ejecución: terraform plan
6. Crear la infraestructura: terraform apply
**Terraform mostrará el plan definitivo y solicitará confirmación antes de crear los recursos.**
7. Obtener la dirección IP pública del balanceador: terraform output -raw ip_publica_balanceador
8. Abrir la dirección obtenida utilizando HTTP: http://<IP_DEL_BALANCEADOR>

Durante el aprovisionamiento inicial, el balanceador puede no responder hasta que las primeras instancias completen su configuración y superen el health check.

La eliminación completa del entorno se explica en la sección [Destrucción de la infraestructura](#destrucción-de-la-infraestructura).

## Ciclo de vida del laboratorio.
Después de ejecutar terraform apply, el laboratorio atraviesa las siguientes etapas:
<br>
<br>
Los tiempos concretos y los resultados obtenidos durante las ejecuciones se documentan en la sección [Operaciones](#operaciones).

### Etapa 1 — Despliegue y aprovisionamiento (≈ 0–3 min)
<br>
Terraform crea los 16 recursos respetando sus dependencias, incluidos la red, los componentes de balanceo y el MIG regional. Luego, el grupo aprovisiona la cantidad mínima de instancias configurada y cada VM ejecuta su startup script para instalar las dependencias necesarias.
<br>
Durante este proceso, la CPU puede alcanzar temporalmente el 100 %. Hasta que una instancia complete su inicialización y supere el health check, el balanceador todavía no dispone de un backend saludable.
<br>

### Etapa 2 — Inicialización y tiempos de gracia (≈ 3–5 min)
<br>
Una vez instaladas las dependencias, Uvicorn comienza a ejecutarse en el puerto 8080. El script encargado de la prueba de carga también se inicia en segundo plano, aunque espera 300 segundos antes de ejecutar stress.
<br>
Durante la inicialización, initial_delay_sec permite que el MIG ignore temporalmente los health checks fallidos utilizados por el autohealing, evitando que una VM todavía en preparación sea recreada prematuramente. Por su parte, cooldown_period indica al autoscaler cuánto tiempo necesita una nueva instancia para inicializarse antes de que sus métricas de utilización se consideren representativas.
<br>
Cuando al menos una instancia supera el health check y queda disponible como backend saludable, el balanceador comienza a responder correctamente:
<br>
<br>

```
  "mensaje": "Instancia activa recibiendo trafico",
  "maquina": "itaca-vm-xxxx"

```

### Etapa 3 — Estrés y scale-out (≈ 5–11 min)
<br>
Tras los 300 segundos de espera, la CPU alcanza el 100 % y supera el umbral configurado. El autoscaler eleva el tamaño objetivo de una a seis instancias y el MIG aprovisiona las cinco réplicas nuevas en paralelo.
<br>
Una vez inicializadas y validadas por los health checks, el balanceador distribuye tráfico entre las seis instancias, verificable mediante el cambio de hostname en las respuestas.
<br>

### Etapa 4 — Estabilización y scale-down (≈ 21–30 min)
<br>
Finalizada la carga, la CPU cae por debajo del umbral. Tras el período de estabilización, el autoscaler reduce el MIG hasta regresar a una instancia, sin interrupciones observables en el servicio.
<br>

### Etapa 5 — Destrucción del entorno
<br>
`terraform destroy` elimina los recursos según sus dependencias, incluidas las instancias administradas por el MIG. Al finalizar, Terraform confirma la destrucción completa y el `state` queda vacío.
<br>

```
Destroy complete! Resources: 16 destroyed.
```

## operaciones
Esta sección documenta la validación práctica de la arquitectura mediante capturas obtenidas durante su ejecución.

### Despliegue de la infraestructura

`terraform plan` validó la configuración y anticipó la creación de 16 recursos. Posteriormente, `terraform apply` ejecutó el despliegue respetando el grafo de dependencias y creando recursos independientes en paralelo.

Al finalizar, Terraform confirmó el aprovisionamiento completo y devolvió la dirección IP pública del balanceador.

### Inicializacion y tiempos de gracia
<br>
En este primer paso, si tomamos la dirección IP del balanceador y la abrimos en el navegador, veremos que la arquitectura temporalmente no responde. Esto es un comportamiento esperado, ya que la infraestructura todavía se encuentra inicializándose y no dispone de un backend saludable.
<br>

**Convergencia inicial de la infraestructura.**

Hasta este punto, el comportamiento observado es el esperado. Solo resta esperar a que finalicen los tiempos de gracia configurados para cada componente:

1. 180 segundos de *cooldown* del autoscaler.
2. 300 segundos de gracia para el health check.
3. 300 segundos de espera (`sleep`) antes de iniciar la carga de CPU.

#### Tras los 180 segundos de \cooldown_period

Finalizado el período de inicialización, el autoscaler comienza a considerar representativas las métricas de CPU de la instancia.

<br>
<p align="center">
  <img src="Imagenes/1 instancia autoscaler buen estado.jpeg" alt="autoscaler 1 ok" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Vista de la instancia con la verificación de estado en buen estado"</em>
</p>
<br>

#### Tras los 300 segundos de initial_delay_sec

Finalizado el período de gracia del autohealing, el health check regional confirma que la instancia responde correctamente y puede recibir tráfico del balanceador.

<br>
<p align="center">
  <img src="Imagenes/1 vm check ok.jpeg" alt="health check 1 ok" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"El health check confirma que la instancia responde correctamente."</em>
</p>
<br>

#### Validación de la aplicación

Con la instancia inicial disponible como backend saludable, la dirección IP del balanceador comienza a devolver una respuesta válida de la aplicación.

### Prueba de carga y scale-out

Tras los 300 segundos de `sleep`, el script ejecuta `stress` y la utilización de CPU alcanza el 100 %.

<br>
<p align="center">
  <img src="Imagenes/cpu al 100 desde ssh.jpeg" alt="top cpu 100" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Conectados por SSH y utilizando el comando <code>top</code>, podemos verificar que la instancia está utilizando el 100 % de CPU."</em>
</p>
<br>

#### Escalado horizontal del MIG

Al superar el umbral de CPU, el autoscaler eleva el tamaño objetivo de una a seis instancias y el MIG aprovisiona las cinco réplicas adicionales en paralelo.

<br>
<p align="center">
  <img src="Imagenes/5 instancias en mal estado desde autoscaler.jpeg" alt="5 instancias en mal estado" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Se observa la creación de cinco nuevas instancias que aún se encuentran en proceso de inicialización."</em>
</p>
<br>

#### Inicialización de las nuevas réplicas

Durante el aprovisionamiento, las cinco instancias nuevas todavía no superan el health check y, por lo tanto, no reciben tráfico del balanceador.

<br>
<p align="center">
  <img src="Imagenes/5 instancias en mal estado otra vista.jpeg" alt="5 instancias en mal estado health check" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Las nuevas instancias aún no completaron su proceso de arranque y, por lo tanto, todavía no responden correctamente."</em>
</p>
<br>

#### Verificación en Compute Engine

Compute Engine confirma que el MIG regional aprovisionó en paralelo las cinco réplicas adicionales, alcanzando un total de seis instancias.

<br>
<p align="center">
  <img src="Imagenes/6 instancias desde compute engine.jpeg" alt="6 instancias creadas" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Vista general mostrando las seis instancias administradas por el Managed Instance Group."</em>
</p>
<br>

### Estado estable y validación del balanceo

Cada réplica repite el proceso de inicialización de la instancia original y comienza a recibir tráfico únicamente después de superar el health check.

#### Vista desde el autoscaler

El autoscaler alcanza el valor configurado en ´´´max_replicas = 6´´´ y mantiene el MIG en su capacidad máxima durante la prueba.
<br>
<p align="center">
  <img src="Imagenes/6 instancias desde autoscaler.jpeg" alt="6 instancias" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"El autoscaler informa que las seis instancias se encuentran bajo carga y que no es posible crear más réplicas debido al límite máximo configurado."</em>
</p>
<br>

#### Seis backends saludables

Una vez finalizada la inicialización, las seis instancias superan el health check y quedan habilitadas para recibir tráfico.

<br>
<p align="center">
  <img src="Imagenes/6 instancias ok desde healthcheck otra vista.jpeg" alt="6 instancias responde" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Todas las instancias responden correctamente a las verificaciones de estado."</em>
</p>

#### Validación del balanceo de carga

Al actualizar repetidamente la aplicación mediante la IP pública del balanceador, las respuestas muestran distintos hostnames y confirman la distribución de solicitudes entre las instancias del MIG.

<br>
<br>
<p align="center">
  <img src="Imagenes/respuesta 051w.jpeg" alt="la instancia 051w responde" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Respuesta generada por la instancia 051w."</em>
</p>
<br>
<br>
<p align="center">
  <img src="Imagenes/respuesta 0frv.jpeg" alt="la instancia 0frv responde" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Respuesta generada por la instancia 0frv."</em>
</p>
<br>
<br>
<p align="center">
  <img src="Imagenes/respuesta m6qk.jpeg" alt="la instancia m6qk responde" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Respuesta generada por la instancia m6qk."</em>
</p>
<br>
<br>

### Ciclo de vida de las VMs

La infraestructura comienza a responder aproximadamente a los cinco minutos. Tras iniciarse la carga de CPU, el autoscaler eleva el tamaño del MIG de una a seis instancias y las nuevas réplicas completan su inicialización alrededor de los minutos 10–11.

Finalizada la prueba de estrés, la CPU disminuye y comienza el scale-down. Entre los minutos 21 y 30, el grupo reduce su capacidad hasta regresar al mínimo configurado de una instancia.

<br>
<p align="center">
  <img src="Imagenes/ciclo de vida de las VMs.jpeg" alt="ciclo de vida de las VMs" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Leyendo la gráfica de izquierda a derecha, el primer pico de la línea roja corresponde a la instalación de dependencias de la instancia inicial. El segundo representa la ejecución de stress, que activa el autoscaler y provoca la creación en paralelo de cinco réplicas. Las nuevas líneas muestran la inicialización y posterior carga de esas instancias. La caída conjunta al final de la gráfica refleja la finalización del estrés y el descenso de CPU previo al scale-down."</em>
</p>
<br>
<br>

### Destrucción de la infraestructura

Finalizadas las pruebas, se ejecutó ´´´terraform destroy´´´ para eliminar los recursos y evitar costos innecesarios. Tras corregir la dependencia implícita documentada en el incidente 5, Terraform destruyó los 16 recursos correctamente y dejó el state vacío.

<br>
<p align="center">
  <img src="Imagenes/Terraform destroy.jpeg" alt="terraform destroy" width="850">
  <br>
  <kbd></kbd> <br>
  <em>"Ejecución del comando <code>terraform destroy</code> para eliminar todos los recursos aprovisionados durante el laboratorio."</em>
</p>
<br>
<br>

## Registro de incidentes y resolución de problemas

### Aprendizajes principales

* **Alta disponibilidad:** configuración de un MIG regional distribuido entre múltiples zonas.
* **Autoscaling:** coordinación del autohealing y el autoscaler durante la inicialización.
* **Networking:** implementación de la proxy-only subnet requerida por el balanceador regional basado en Envoy.
* **Terraform:** administración del ciclo de vida, dependencias inferidas mediante referencias y dependencias explícitas con `depends_on`.
* **Troubleshooting:** análisis de startup scripts, procesos ejecutados con `nohup` y finales de línea CRLF/LF.

### Incidente 1 — Inestabilidad del Managed Instance Group

**Síntoma:** las instancias entraban en ciclos de creación y eliminación, mientras el autoscaler generaba réplicas antes de que comenzara la prueba de carga.

**Causa raíz:** la instalación de paquetes y dependencias saturaba temporalmente la CPU de las instancias `e2-micro`. El autoscaler interpretaba esa utilización como demanda real y, simultáneamente, el autohealing recibía health checks fallidos porque Uvicorn todavía no respondía en el puerto `8080`.

**Resolución:**

| Configuración             | Función                                                                           |
| ------------------------- | --------------------------------------------------------------------------------- |
| `initial_delay_sec = 300` | Evita que el autohealing recree una VM mientras todavía se inicializa.            |
| `cooldown_period = 180`   | Impide utilizar inmediatamente sus métricas de CPU para decisiones de scale-out.  |
| `sleep 300`               | Retrasa la prueba de estrés y la separa del consumo generado durante el arranque. |

**Lección aprendida:** el autoscaler observa utilización de recursos, pero no puede determinar por sí mismo si proviene de usuarios o del aprovisionamiento. En producción, una imagen preconstruida con Packer o una aplicación contenerizada puede reducir el trabajo realizado durante el arranque, aunque no elimina la necesidad de configurar correctamente los períodos de inicialización.

### Incidente 2 — Fallo del startup script por finales de línea CRLF

**Síntoma:** las VMs se creaban correctamente, pero la API no respondía en el puerto `8080`. Terraform finalizaba sin errores porque no valida la ejecución interna del startup script.

**Causa raíz:** `main.tf`, editado desde Windows, contenía finales de línea CRLF (`\r\n`). Al ejecutar en Debian el script Bash incluido en el archivo, esos caracteres provocaban errores de interpretación.

**Resolución:** se normalizaron los finales de línea a LF (`\n`) desde PowerShell:

```powershell
(Get-Content main.tf -Raw) -replace "`r`n", "`n" | Set-Content main.tf -NoNewline
```

El diagnóstico se confirmó revisando los registros del startup script mediante el puerto serie de la VM.

**Lección aprendida:** `terraform apply` puede completar correctamente aunque falle un proceso ejecutado dentro del sistema operativo. Los scripts Bash deben conservar finales de línea LF; para prevenir nuevas conversiones también puede definirse esta regla en `.gitattributes`.

### Incidente 3 — Topología de red incompleta para el balanceador regional

**Síntoma:** el balanceador no podía comunicarse con los backends, los health checks permanecían en estado `unhealthy` y el startup script fallaba al descargar paquetes.

**Causa raíz:** la configuración inicial no contemplaba tres requisitos independientes:

* Una proxy-only subnet para los proxies Envoy.
* Salida a internet para las VMs sin IP pública.
* Reglas de firewall para los proxies y los health checks de Google.

**Resolución:** se creó `itaca_proxy` con la configuración requerida:

```hcl
purpose = "REGIONAL_MANAGED_PROXY"
role    = "ACTIVE"
```

Cloud Router y Cloud NAT proporcionaron salida a internet sin asignar IPs públicas a las VMs. Además, se habilitó el puerto `8080` desde dos orígenes diferentes:

* `10.129.0.0/23`, utilizado por los proxies Envoy.
* `35.191.0.0/16` y `130.211.0.0/22`, utilizados por los health checks de Google.

**Lección aprendida:** un Application Load Balancer externo regional necesita una proxy-only subnet y reglas diferentes para el tráfico de los proxies y las verificaciones de estado. Estos son [requisitos de la arquitectura](https://docs.cloud.google.com/load-balancing/docs/https/setting-up-reg-ext-https-lb), no componentes opcionales.

### Incidente 4 — Ejecución no persistente del proceso de estrés

**Síntoma:** después del período de espera, el proceso `stress` no siempre permanecía ejecutándose y no existía un registro independiente que permitiera diagnosticar su finalización.

**Causa raíz:** ejecutar un comando con `&` solamente lo envía a segundo plano. Esto no proporciona protección frente a señales de cierre ni una administración confiable de sus logs.

**Resolución:** el proceso de estrés se separó en un script independiente:

```bash
cat > /home/estresar.sh << 'BASH_EOF'
#!/bin/bash
sleep 300
stress --cpu $(nproc) --timeout 960
BASH_EOF

chmod +x /home/estresar.sh
nohup /home/estresar.sh > /home/estresar.log 2>&1 &
```

`nohup` permite ignorar la señal `SIGHUP`, mientras que `> /home/estresar.log 2>&1` conserva tanto la salida estándar como los errores. El heredoc entre comillas simples evita que `$(nproc)` se evalúe al crear el archivo y permite que se ejecute posteriormente dentro de cada VM.

**Lección aprendida:** `&` y `nohup` cumplen funciones diferentes. Para este laboratorio, `nohup` permite ejecutar y registrar la carga artificial; en un entorno productivo sería preferible administrar la aplicación mediante `systemd` u otro supervisor de procesos.

### Incidente 5 — Dependencia oculta durante `terraform destroy`

**Síntoma:** durante la destrucción, Google Cloud rechazó la eliminación de la proxy-only subnet:

```text
Error 400: The subnetwork resource 'itaca-subnetwork-proxy'
is already being used by 'itaca-forwarding-rule'
```

La destrucción quedaba incompleta y debía ejecutarse nuevamente después de corregir el orden.

**Causa raíz:** Google Cloud relacionaba internamente el forwarding rule con la proxy-only subnet, pero esa relación no aparecía como una referencia directa en Terraform. Por ello, Terraform no podía inferir el orden requerido y trataba de eliminar ambos recursos en paralelo.

**Resolución:** se declaró la dependencia explícitamente en el forwarding rule:

```hcl
depends_on = [google_compute_subnetwork.itaca_proxy]
```

De esta forma, Terraform crea primero la subred y, durante la destrucción, invierte el orden para eliminar primero el forwarding rule.

**Lección aprendida:** Terraform infiere dependencias mediante referencias entre recursos. Cuando una dependencia existe dentro de la API del proveedor pero no aparece en la configuración, debe declararse explícitamente mediante `depends_on`.

## FinOps y análisis de costos

La siguiente estimación considera la infraestructura ejecutándose durante 730 horas mensuales en `southamerica-west1`, con una dirección pública para Cloud NAT y tráfico mínimo.

| Recurso                   |   1 instancia |  6 instancias |
| ------------------------- | ------------: | ------------: |
| Application Load Balancer |     USD 18,25 |     USD 18,25 |
| Cloud NAT e IP pública    |      USD 4,67 |      USD 9,78 |
| Instancias `e2-micro`     |      USD 8,74 |     USD 52,44 |
| Discos estándar de 10 GB  |      USD 0,40 |      USD 2,40 |
| **Total estimado**        | **USD 32,06** | **USD 82,87** |

Cloud Router no incorpora un cargo fijo independiente. Cloud NAT cobra por cada VM que utiliza la pasarela, por su dirección IP pública y por los datos procesados. El balanceador cobra la regla de reenvío y el volumen de tráfico procesado. Por lo tanto, estos valores no incluyen transferencia hacia internet, procesamiento de datos ni posibles cargos de Cloud Logging. Las tarifas pueden verificarse en la documentación de [Cloud NAT](https://cloud.google.com/nat/pricing), [Cloud Load Balancing](https://cloud.google.com/load-balancing/pricing) y [Persistent Disk](https://cloud.google.com/compute/disks-image-pricing).

### Estrategia de mitigación de costos

El laboratorio tiene un ciclo de vida efímero. Al finalizar las pruebas, `terraform destroy` elimina los recursos administrados en el state. Sin embargo, la operación no garantiza la eliminación de recursos creados fuera de Terraform ni de aquellos cuya destrucción haya fallado; por eso se debe comprobar que el state quede vacío y que no permanezcan recursos activos en Google Cloud.

Con tráfico mínimo y una ejecución inferior a una hora, el laboratorio puede costar menos de USD 0,10. Este valor es una estimación: el importe efectivo debe verificarse mediante Cloud Billing.

---
## Colofón: por qué Ítaca.
Durante el documento se lee el nombre "Ítaca". Ítaca hace alusión al hogar del protagonista de la Ilíada de Homero, Odiseo (Ὀδυσσεύς en griego), rey de Ítaca, donde su amada esposa Penélope (Πηνελόπεια) junto a su hijo Telémaco (Τηλέμαχος) lo esperaban ansiosamente día a día. Los romanos, como es sabido en la historia, tomaron mucho de la cultura griega y lo adaptaron: Odiseo se volvió Ulises, Penélope se volvió Penelopea y Telémaco se volvió Telemachus. Todos conocemos la historia de la Odisea, pero eso no es lo importante.

Lo importante de esto es el origen etimológico de la palabra Penélope. Aunque se discute, se cree que "Pene" viene de "hilo, tejido, trama". Por otro lado, Florencia viene del latín, de alguna parte del centro de Italia, y significa "florida", "en flor" o "aquella que da frutos y florece". Esto es importante porque, al igual que Penélope y Odiseo, compartimos una vida de amor juntos. Vos y Máximo —mi Telémaco, que al igual que en la historia era solo un bebé cuando esta odisea empezó— son mi motor, el hilo con el que hacemos fuerte nuestra Ítaca: nuestro hogar de calor, seguridad y felicidad.
<br>
<br>
## contacto.
<p align="center">
  Do you want to connect with me or learn more about my projects on Google Cloud? <br>
  <a href="https://www.linkedin.com/in/ulises-acu%C3%B1a-bianchi-6a36961b4/" target="_blank" rel="noopener noreferrer">
    <img src="https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white" alt="LinkedIn Profile">
  </a>
  <br>
  <sub>developed with ❤️ by Ulises Acuña Bianchi - 2026</sub>
</p>
