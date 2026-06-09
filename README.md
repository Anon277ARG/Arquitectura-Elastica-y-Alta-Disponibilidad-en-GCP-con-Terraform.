# Arquitectura Elástica y Alta Disponibilidad en GCP con Terraform.

### Resumen del proyecto
Arquitectura elástica y de alta disponibilidad desplegada en Google Cloud Platform mediante Terraform. El objetivo principal fue diseñar una plataforma resiliente capaz de escalar automáticamente (*scale-out*) ante picos de demanda y regresar a un estado de bajo costo (*scale-in*) cuando la carga disminuye.

**Características Principales:**
- **Aislamiento y Zero-Trust:** VPC privada sin IPs públicas, acceso seguro mediante IAP y salida a internet vía Cloud NAT.
- **Cómputo Elástico:** Regional Managed Instance Group (MIG) con Auto-healing.
- **Autoscaling:** Basado en umbrales de uso de CPU.
- **Balanceo de Nueva Generación:** External Managed Application Load Balancer (Proxy Envoy).

**Resultados Obtenidos:**
- Escalado dinámico de 1 a 6 instancias validado mediante pruebas de estrés.
- Tolerancia a fallos con distribución multi-zona.
- Infraestructura 100% reproducible mediante código (IaC).

*Durante el desarrollo de este laboratorio, se documentaron incidentes reales de despliegue relacionados con el flapping del autoscaler, requisitos de red modernos, startup scripts y dependencias implícitas en Terraform, los cuales se detallan en la sección de Troubleshooting.*

### Aviso importante.
Este proyecto representa la Fase 1 (Stateless) de una arquitectura de laboratorio. El diseño prioriza estrictamente el análisis del cómputo elástico y el comportamiento de la red por sobre la persistencia de datos, la cual será abordada en la Fase 2.

## Diagrama de arquitectura visual.
<figure>
  <img src="Imagenes/Diagrama.png" alt="Arquitectura fase 1 y fase 2">
  <figcaption><em>Arquitectura stateless — Fase 1. El componente Cloud SQL representa la capa de persistencia planificada para la Fase 2.</em></figcaption>
</figure>

### Stack tecnologico y Decisiones de Diseño.

#### Stack Tecnológico. 
- Infraestructura como Código: Terraform
- Proveedor Cloud: Google Cloud Platform (GCP)
- Cómputo Elástico: Compute Engine (e2-micro), Regional Managed Instance Group (MIG)
- Balanceo de Carga: Application Load Balancer (External Managed)
- Redes Perimetrales: Custom VPC, Cloud NAT, Cloud Router, Proxy Subnet
- Seguridad Zero-Trust: Identity-Aware Proxy (IAP)
- Capa de Aplicación: Debian 11, Bash (Startup Scripts), Python 3, FastAPI, Uvicorn, Stress

### requisitos
- **cuenta de Google Cloud Computing GCP** - un proyecto de GCP creado y activo, cuenta de facturacion (Billing) vinculada al proyecto.
- **APIs Habilitadas** - la api de compute engine habilitada en el proyecto.
- **Herramientas de línea de comandos (CLI) y terraform** - terraform instalado en tu entorno local, Gcloud instalado y autenticado.
- **Permisos de IAM** - tener los permisos en GCP para crear redes y máquinas virtuales.

### despliegue
1. Clonar el repositorio: git clone [https://github.com/tu-usuario/tu-repo.git](https://github.com/Anon277ARG/Arquitectura-Elastica-y-Alta-Disponibilidad-en-GCP-con-Terraform.).
2. Autenticar en gcp: gcloud auth application-default login.
3. Configurar el proyecto: gcloud config set project cloud-lab-493.
4. Iniciar Terraform: terraform init.
5. Verificar los cambios antes de aplicar: terraform plan.
6. PASO OPCIONAL, este paso solo es importante si estamos en un entorno Windows, en caso contrario se puede saltear ```(Get-Content main.tf -Raw) -replace "`r`n", "`n" | Set-Content main.tf -NoNewline ``` para asegurarnos que no hayan incompatibilidades entre el entorno windows y el linux de gcp.
7. Aplicar la infraestructura: terraform apply.
8. Una vez obtenida la IP, abrí `http://<ip>` en el navegador. Durante los primeros 5 minutos la arquitectura no va a responder, ese comportamiento está documentado en la sección de operaciones.
9. Destruir el entorno cuando termine: terraform destroy.

### Comportamiento Esperado del Sistema
Esta sección describe el ciclo de vida completo de la arquitectura desde el momento del despliegue hasta el scale-down final. Cada comportamiento descripto es intencional y responde a decisiones de diseño documentadas en la sección de componentes.

#### Resumen de tiempos del ciclo de vida
- **0 - 5 min** — Terraform apply completo, infraestructura creada.
- **5 min** — IP del balanceador sin respuesta, comportamiento esperado.
- **~5 min** — Primera instancia en buen estado, IP comienza a responder.
- **~5 min** — Script de estrés activa CPU al 100%.
- **~6 – 7 min** — Autoscaler detecta la carga y escala a 6 instancias.
- **~10 – 11 min** — 6 instancias en buen estado, balanceo activo entre todos los nodos.
- **~21 min** — Proceso de estrés finaliza, CPU cae.
- **~24 min** — Scale-down inicia.
- **~27 – 30 min** — Sistema regresa a 1 instancia activa.

#### Fase 1 — Despliegue (0 – 3 min)
<br>
terraform apply crea los 16 recursos en GCP en orden según el grafo de dependencias.
El MIG levanta una única instancia (min_replicas = 1) en una de las zonas configuradas.
La VM inicia el startup script: actualiza repositorios, instala Python, FastAPI y la herramienta stress.
Durante esta fase la CPU de la e2-micro sube naturalmente al 100% por la instalación de dependencias.
La IP del balanceador no responde. Este es el comportamiento esperado.


#### Fase 2 — Inicialización y tiempos de gracia (3 – 5 min)
<br>
El startup script finaliza la instalación y levanta Uvicorn en el puerto 8080 con &.
El proceso estresar.sh se lanza con nohup y entra en sleep 300, esperando en segundo plano.
El health check comienza a evaluar la instancia cada 10 segundos en la ruta GET /health.
El initial_delay_sec = 300 del MIG protege la instancia durante este período, evitando que sea marcada como unhealthy antes de estar lista.
El cooldown_period = 180 del autoscaler ignora los picos de CPU de esta fase, evitando réplicas prematuras.
Al cabo de aproximadamente 5 minutos la instancia pasa el health check y queda en buen estado.
La IP del balanceador comienza a responder. Navegando a http://<ip> se obtiene la siguiente respuesta:
  
```
  "mensaje": "Instancia activa recibiendo trafico",
  "maquina": "itaca-vm-xxxx"

```

#### Fase 3 — Estrés y autoescalado horizontal (5 – 11 min)
<br>
El sleep 300 del script de estrés termina y stress --cpu $(nproc) ejecuta, llevando la CPU al 100%.
El autoscaler detecta que el uso de CPU supera el umbral configurado (80%) y toma la decisión de escalar.
El MIG crea 5 réplicas adicionales hasta alcanzar el máximo configurado (max_replicas = 6).
Las 5 nuevas instancias repiten el ciclo de la Fase 1 y Fase 2 de forma simultánea.
Durante este período las nuevas instancias están en mal estado en el health check, comportamiento esperado mientras completan su inicialización.
Al cabo de aproximadamente 10 – 11 minutos desde el deploy inicial, las 6 instancias están en buen estado.
Refrescando repetidamente http://<ip> en el navegador, el campo máquina cambia entre los hostnames de las 6 instancias, demostrando que el balanceador distribuye el tráfico entre todos los nodos activos.


#### Fase 4 — Estabilización y scale-down (21 – 30 min)
<br>
El proceso stress finaliza tras el timeout configurado de 960 segundos (~16 minutos desde que arrancó).
El uso de CPU cae en todas las instancias por debajo del umbral del 80%.
El autoscaler detecta que la carga no justifica mantener 6 réplicas e inicia el scale-down gradual.
El MIG termina las instancias excedentes respetando el cooldown_period, asegurando que no haya interrupciones de servicio durante la reducción.
El sistema regresa a 1 instancia activa (min_replicas = 1).
La IP del balanceador sigue respondiendo durante todo el proceso de scale-down.


#### Fase 5 — Destrucción del entorno
<br>
Ejecutar terraform destroy en la terminal.
Terraform destruye los recursos en orden inverso al grafo de dependencias.
El MIG termina todas las instancias activas antes de poder eliminarse. Este proceso puede tomar entre 5 y 15 minutos dependiendo de cuántas instancias estén corriendo.
No interrumpir el proceso. Ejecutar Ctrl+C desincroniza el state de Terraform con GCP.
Al finalizar, la terminal confirma la destrucción completa:

Destroy complete! Resources: 16 destroyed.

### operaciones 
#### Siguiendo las instrucciones descritas más arriba vamos a desplegar esta arquitectura.
Después de clonar este repositorio, autenticarnos en los servicios de Google, iniciar Terraform y solucionar incompatibilidades entre sistemas operativos, los pasos que se establecen son los siguientes
- ```.\terraform.exe plan``` y ``` .\terraform.exe apply``` al usar estos comandos terraform le pregunta al proveedor si dichos recursos ya existen, trae el estado de la arquitectura actual y actualiza nuestro archivo ```terraform.tfstate``` documento que registra el estado actual de nuestra arquitectura, también crea un grafo de dependencias, terraform no puede crear una subred si primero no tiene una red.

#### Despliegue de la infraestructura

Se ejecutó `terraform plan` para validar la configuración y previsualizar los cambios que serían aplicados en Google Cloud. Terraform determinó la creación de 16 recursos necesarios para la arquitectura.

Posteriormente, mediante `terraform apply`, se autorizó y ejecutó el despliegue de la infraestructura. Terraform creó los recursos respetando sus dependencias y aprovechando la ejecución en paralelo cuando fue posible.

Al finalizar el proceso, los 16 recursos fueron aprovisionados correctamente y se obtuvo la dirección IP pública del balanceador de cargas para acceder a la aplicación.

#### Fase de Inicializacion y tiempos de gracia.
<br>

En este primer paso, si tomamos la dirección IP del balanceador y la abrimos en el navegador, veremos que la arquitectura temporalmente no responde. Esto es un comportamiento esperado, ya que la infraestructura se encuentra intencionalmente "congelada" por diseño para proteger el ciclo de vida de los recursos.
<br>

##### Convergencia inicial de la infraestructura

Hasta este punto, el comportamiento observado es el esperado. Solo resta esperar a que finalicen los tiempos de gracia configurados para cada componente:

1. 180 segundos de *cooldown* del autoscaler.
2. 300 segundos de gracia para el health check.
3. 300 segundos de espera (`sleep`) antes de iniciar la carga de CPU.

###### Pasados los 180 segundos de cooldown del autoscaler

La instancia ya se encuentra operativa y el autoscaler la considera saludable.

<br>
<figure>
  <img src="Imagenes/1 instancia autoscaler buen estado.jpeg" alt="autoscaler 1 ok">
  <figcaption><em>Vista del autoscaler mostrando que la instancia ya se encuentra operativa.</em></figcaption>
</figure>
<br>

###### Pasados los 300 segundos del health check

El health check confirma que la instancia responde correctamente.

<br>
<figure>
  <img src="Imagenes/1 vm check ok.jpeg" alt="health check 1 ok">
  <figcaption><em>El health check confirma que la instancia responde correctamente.</em></figcaption>
</figure>
<br>

#### En este punto, si accedemos a la dirección IP proporcionada por Terraform y actualizamos el navegador, deberíamos recibir una respuesta válida de la aplicación.

###### Pasados los 300 segundos de espera (`sleep`)

La carga artificial comienza a ejecutarse y la instancia alcanza el 100 % de utilización de CPU.

<br>
<figure>
  <img src="Imagenes/cpu al 100 desde ssh.jpeg" alt="top cpu 100">
  <figcaption><em>Conectados por SSH y utilizando el comando <code>top</code>, podemos verificar que la instancia está utilizando el 100 % de CPU.</em></figcaption>
</figure>
<br>

###### El autoscaler detecta la carga y crea cinco instancias adicionales

Al superarse el umbral configurado, el autoscaler inicia la creación de nuevas réplicas para absorber la carga.

<br>
<figure>
  <img src="Imagenes/5 instancias en mal estado desde autoscaler.jpeg" alt="5 instancias en mal estado">
  <figcaption><em>Se observa la creación de cinco nuevas instancias que aún se encuentran en proceso de inicialización.</em></figcaption>
</figure>
<br>

###### Las nuevas instancias todavía no responden al health check

Este comportamiento es esperado, ya que las instancias aún se encuentran en proceso de inicialización.

<br>
<figure>
  <img src="Imagenes/5 instancias en mal estado otra vista.jpeg" alt="5 instancias en mal estado health check">
  <figcaption><em>Las nuevas instancias aún no completaron su proceso de arranque y, por lo tanto, todavía no responden correctamente.</em></figcaption>
</figure>
<br>

###### Vista desde Compute Engine

Se observa un total de seis instancias administradas por el Managed Instance Group.

<br>
<figure>
  <img src="Imagenes/6 instancias desde compute engine.jpeg" alt="6 instancias creadas">
  <figcaption><em>Vista general mostrando las seis instancias administradas por el Managed Instance Group.</em></figcaption>
</figure>
<br>

##### Estado estable del clúster

El comportamiento observado en las nuevas instancias es idéntico al de la instancia original. Cada una debe completar su proceso de inicialización antes de ser considerada saludable y comenzar a recibir tráfico.

1. 180 segundos de *cooldown* del autoscaler.
2. 300 segundos de gracia para el health check.
3. 300 segundos de espera (`sleep`) antes de iniciar la carga de CPU.

###### Vista desde el autoscaler

El autoscaler informa que se alcanzó el número máximo de instancias configurado para el laboratorio.

<br>
<figure>
  <img src="Imagenes/6 instancias desde autoscaler.jpeg" alt="6 instancias">
  <figcaption><em>El autoscaler informa que las seis instancias se encuentran bajo carga y que no es posible crear más réplicas debido al límite máximo configurado.</em></figcaption>
</figure>
<br>

###### Estado de los health checks

Las seis instancias responden correctamente a las verificaciones de estado.

<br>
<figure>
  <img src="Imagenes/6 instancias ok desde healthcheck otra vista.jpeg" alt="6 instancias responde">
  <figcaption><em>Todas las instancias responden correctamente a las verificaciones de estado.</em></figcaption>
</figure>
<br>

#### Una vez finalizado el período de espera, al actualizar repetidamente la aplicación mediante la IP pública del balanceador, puede observarse cómo las solicitudes son distribuidas entre distintas instancias del grupo.

<br>
<br>

<figure>
  <img src="Imagenes/respuesta 051w.jpeg" alt="la instancia 051w responde">
  <figcaption><em>Respuesta generada por la instancia 051w.</em></figcaption>
</figure>

<br>
<br>

<figure>
  <img src="Imagenes/respuesta 0frv.jpeg" alt="la instancia 0frv responde">
  <figcaption><em>Respuesta generada por la instancia 0frv.</em></figcaption>
</figure>

<br>
<br>

<figure>
  <img src="Imagenes/respuesta m6qk.jpeg" alt="la instancia m6qk responde">
  <figcaption><em>Respuesta generada por la instancia m6qk.</em></figcaption>
</figure>

<br>
<br>

### Ciclo de vida de las VMs

La infraestructura alcanza su estado operativo aproximadamente a los 5 minutos del despliegue. A los 10 minutos se inicia el escalado horizontal automático, alcanzando el máximo configurado de 6 instancias. Una vez finalizado el proceso de estrés de CPU (16 minutos), el autoscaler comienza la fase de escalado descendente (*scale-down*), reduciendo progresivamente la cantidad de nodos hasta regresar a una única instancia para optimizar costos operativos.

<br>
<figure>
  <img src="Imagenes/ciclo de vida de las VMs.jpeg" alt="ciclo de vida de las VMs">
  <figcaption><em>La gráfica muestra el comportamiento de una instancia durante todo su ciclo de vida. Inicialmente se observa un pico de CPU asociado a la instalación de dependencias. Posteriormente, la carga disminuye hasta que se ejecuta el proceso de estrés, provocando un nuevo incremento en el consumo de CPU que activa el autoscaler. Las nuevas instancias replican el mismo patrón de inicialización y convergencia.</em></figcaption>
</figure>
<br>
<br>

### Destrucción de la infraestructura

Una vez finalizadas las pruebas, se recomienda eliminar todos los recursos creados para evitar costos innecesarios. Terraform permite destruir la infraestructura completa de forma controlada mediante un único comando, garantizando que los recursos sean eliminados respetando sus dependencias.

<br>
<figure>
  <img src="Imagenes/Terraform destroy.jpeg" alt="terraform destroy">
  <figcaption><em>Ejecución del comando <code>terraform destroy</code> para eliminar todos los recursos aprovisionados durante el laboratorio.</em></figcaption>
</figure>
<br>
<br>

#### Notas de Diseño.
- Arquitectura Stateless (Fase 1): Esta primera versión fue diseñada de forma intencional sin capa de persistencia (Base de Datos) para enfocarnos única y puramente en validar el comportamiento del cómputo elástico y la distribución de red. La capa de datos se abordará en la Fase 2.
- Recursos Planos vs. Módulos (Claridad Didáctica): Se optó por utilizar resources individuales de Terraform en lugar de módulos prefabricados. Esto garantiza un control granular sobre cada parámetro y aporta claridad didáctica, ya que cada bloque de código refleja de forma explícita un componente de la topología real.
- Seguridad Zero-Trust y Acceso vía IAP: Las instancias carecen de IP pública y el puerto 22 (SSH) no está abierto a todo internet. La regla de firewall allow-ssh-itaca solo permite tráfico desde la red 35.235.240.0/20 (rango oficial de Identity-Aware Proxy de Google), mediando el acceso seguro sin necesidad de Bastion Hosts.
- Topología de Red Aislada (Custom VPC): Se desactivó la creación automática de subredes (auto_create_subnetworks = false) para evitar solapamientos de IP. La salida a internet de las VMs para descargar paquetes de sistema se resolvió usando Cloud NAT y Cloud Router, manteniendo el clúster 100% aislado.
- Alta Disponibilidad Multi-Zona (Regional MIG): El Managed Instance Group no es zonal, es Regional. Al distribuir las políticas en múltiples zonas (southamerica-west1-a y b), se garantiza que si un centro de datos entero de Google experimenta una interrupción, la arquitectura siga operando.
- Balanceo de Carga de Nueva Generación y Subred Proxy: Para implementar el Load Balancer HTTP regional (EXTERNAL_MANAGED), Google Cloud exige una subred dedicada. Se creó itaca_proxy con el propósito REGIONAL_MANAGED_PROXY, aislando el tráfico de los proxies (Envoy) del tráfico interno de las VMs.
- Infraestructura Inmutable (Startup Scripts): Se utilizó el patrón de Startup Script inyectado en la Metadata. Las instancias nacen limpias (imagen base de Debian 11) y se autoconfiguran al bootear instalando FastAPI y Uvicorn, facilitando la rotación de nodos ante futuras actualizaciones de la API.
- Estabilidad de Métricas y Prevención de Flapping: Al usar máquinas pequeñas (e2-micro), el simple hecho de instalar dependencias eleva la CPU al 100%. Para evitar que el autoscaler lea esto como un "falso positivo" y cree réplicas innecesarias (flapping), se separó la fase de aprovisionamiento de la de carga real sincronizando tiempos lógicos: un initial_delay_sec de 300s en el MIG, un cooldown_period de 180s en el Autoscaler, y un sleep de 300s en el script de estrés.

### Componentes

<details>
<summary>Descripción detallada de los componentes de la arquitectura</summary>

<br>

#### Redes

- **VPC personalizada** denominada `itaca-network`, desplegada en la región de Santiago. La configuración más relevante es la desactivación de la creación automática de subredes, permitiendo un control total sobre el direccionamiento IP.

```terraform
resource "google_compute_network" "itaca_network" {
  name                    = "itaca-network"
  routing_mode            = "GLOBAL"
  auto_create_subnetworks = false
}
```

- **Subred privada** denominada `itaca-subnetwork`, utilizada para alojar las instancias del Managed Instance Group. Se habilitó `private_ip_google_access` para permitir el acceso a los servicios de Google sin necesidad de direcciones IP públicas.

```terraform
resource "google_compute_subnetwork" "itaca_subnet" {
  name                     = "itaca-subnetwork"
  region                   = var.region
  ip_cidr_range            = "10.42.0.0/24"
  network                  = google_compute_network.itaca_network.id
  private_ip_google_access = true
}
```

- **Proxy-only subnet** denominada `itaca-subnetwork-proxy`, requerida por los Application Load Balancers regionales. Esta subred es utilizada por los proxies administrados por Google para enrutar tráfico hacia los backends.

```terraform
resource "google_compute_subnetwork" "itaca_proxy" {
  name          = "itaca-subnetwork-proxy"
  region        = var.region
  ip_cidr_range = "10.129.0.0/23"
  network       = google_compute_network.itaca_network.id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}
```

- **Cloud Router**, responsable de proporcionar las rutas necesarias para que las instancias privadas puedan acceder a Internet mediante Cloud NAT.

```terraform
resource "google_compute_router" "itaca_router" {
  name    = "itaca-router"
  region  = var.region
  network = google_compute_network.itaca_network.id
}
```

- **Cloud NAT**, encargado de proporcionar salida a Internet para las instancias privadas sin necesidad de asignar direcciones IP públicas.

```terraform
resource "google_compute_router_nat" "itaca_nat" {
  name                               = "intaca-mig-updatenat"
  router                             = google_compute_router.itaca_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ALL"
  }
}
```

### Firewall
- reglas de firewall con el nombre "itaca-firewall, itaca-health-check, allow-ssh-itaca" 
- todas las reglas con el mismo tag para evitar confuciones "itaca-firewalls"
#### abieros los puertos y las ips
- "22 y 35.235.240.0/20" para la conexions ssh
- "8080 y 10.129.0.0/23" para la conexion del proxy con el load balancer
- "8080 y 35.191.0.0/16, 130.211.0.0/22" para los health check
#### codigo de itaca-firewall
```
  resource "google_compute_firewall" "itaca_firewall" {
  name    = "itaca-firewall"
  network = google_compute_network.itaca_network.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["10.129.0.0/23"]

  target_tags = ["itaca-firewalls"]
  }
```
#### codigo de itaca-health-check
```
resource "google_compute_firewall" "itaca_health_check" {
  name    = "itaca-health-check"
  network = google_compute_network.itaca_network.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  target_tags = ["itaca-firewalls"]
}
```
#### codigo de allow-ssh-itaca
```
resource "google_compute_firewall" "allow_ssh_itaca" {
  name        = "allow-ssh-itaca"
  network     = google_compute_network.itaca_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]

  target_tags = ["itaca-firewalls"]
}
```
### BackEnds
#### MAnage Intance Group con la siguiente configuracion
- con el nombre "itaca-mig
- conectado al puerto 8080
- configurado en la region santiago
- initial delay de 300 segundos de delay como health check policy, para que las VMs se pongan en linea.
- politicas de distribucion en las zonas a y b de la respectiva region.
##### codigo del Manage Instance Group
```
resource "google_compute_region_instance_group_manager" "mig" { 
   name = "itaca-mig"
   base_instance_name = "itaca-vm-"
   region = var.region
   version {
     instance_template = google_compute_instance_template.mig_template.id
   }
   named_port {
      name = "http"
      port = 8080
    }
   distribution_policy_zones = [
     "${var.region}-a",
     "${var.region}-b",
     ]
   auto_healing_policies {
     health_check = google_compute_region_health_check.itaca_check.id
     initial_delay_sec = 300
   }
  }
```
#### mig template con la siguiente configuracion
- nombre: virtual-machine-template
- tag: "itaca-firewalls" para llamar a todos los firewalls
- instancia: e2-Micro, no es necesario mas.
- bloqueo de enrutamiento no autorizado para que las instancias actuen como nodos finales.
- con la imagen de Debian 11
- con la interfaz de red de itaca Network viviendo dentro de Itaca Subnet.
**configuracion del template**
```
resource "google_compute_instance_template" "mig_template" {
  name        = "virtual-machine-template"
  description = "tose are thet templates used by the manage instance group."

  tags = ["itaca-firewalls"]

  labels = {
    environment = "virtual_machine"
  }

  instance_description = "description assigned to instances"
  machine_type         = "e2-micro"
  can_ip_forward       = false

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }
  disk {
    source_image      = "debian-cloud/debian-11"
    auto_delete       = true
    boot              = true
  }
  network_interface {
    network = google_compute_network.itaca_network.id
    subnetwork = google_compute_subnetwork.itaca_subnet.id
  }
```
- en la parte de meta data como Startup script que despliega la API para responder inmediatamente a los health checks, y lanza un proceso en segundo plano que, tras 300 segundos de delay, estresa la CPU al 100% para detonar el autoscaling, esto se definio asi ya que la instancia es una e2-Micro y al instalar las dependencias sube el uso de la CPU al 100% activando el autoscaler.
**script de inicio**
```
  metadata = {
    "serial-port-enable" = "true"
    "startup-script"     = <<-EOF
      #!/bin/bash
      apt-get update -y
      apt-get install -y python3 python3-pip stress
      pip3 install fastapi uvicorn

      cat > /home/main.py << 'PYEOF'
from fastapi import FastAPI
import socket

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/")
def home():
    return {
        "mensaje": "Instancia activa recibiendo trafico",
        "maquina": socket.gethostname()
    }
PYEOF
      cat > /home/estresar.sh << 'BASH_EOF'
#!/bin/bash
sleep 300
stress --cpu $(nproc) --timeout 960
BASH_EOF
      chmod +x /home/estresar.sh
      python3 -m uvicorn main:app --host 0.0.0.0 --port 8080 --app-dir /home &
      nohup /home/estresar.sh > /home/estresar.log 2>&1 &
    EOF
  }
}
```
#### autoscaler con la siguiente configuracion
- nombre: "autoscaler-itaca"
- politica de autoscaling como 1 en replicas minimas y 6 en replicas maximas
- un cooldown period de 180 segundos para asegurarnos la no creacion de replicas indeseadas.
- como politica de replicacion se configuro uso de CPU al 80%.
```
resource "google_compute_region_autoscaler" "itaca_autoscaler" {
 name = "autoscaler-itaca"
 region = var.region
 target = google_compute_region_instance_group_manager.mig.id
 autoscaling_policy {
   min_replicas = 1
   max_replicas = 6
   cooldown_period = 180
   cpu_utilization {
     target = 0.8
   }
 }
}
```
#### servicio Back end con la siguiente configuracion
- nombre: "itaca-backend-service"
- protocolo: HTTP
- esquema de balanceo de carga como "External Managed" usando el nuevo esquema y dandole sentido a la subnet proxy
- modo de Balanceo configurado en "Utilization" en base al uso
- capacidad de scaler en 1.0
```
resource "google_compute_region_backend_service" "itaca_backend" {
  name = "itaca-backend-service"
  region = var.region
  protocol = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks = [google_compute_region_health_check.itaca_check.id]
  backend {
    group = google_compute_region_instance_group_manager.mig.instance_group
    balancing_mode = "UTILIZATION"
    capacity_scaler = 1.0
  }
}
```
### Load Balancer
#### Forwarding rule como puerta de acceso a la internet publica
```
resource "google_compute_forwarding_rule" "itaca-forwarding-rule" { 
  name = "itaca-forwarding-rule"
  region = var.region 
  target = google_compute_region_target_http_proxy.itaca_target_proxy.id
  port_range = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  network = google_compute_network.itaca_network.id
  depends_on = [google_compute_subnetwork.itaca_proxy]
}
```
#### Target proxy como intermediario y procesador del tráfico
```
resource "google_compute_region_target_http_proxy" "itaca_target_proxy" { 
  name = "itaca-target-proxy"
  region = var.region
  url_map = google_compute_region_url_map.itaca_url_map.id
}
```
#### URL Map como como enrutador principal
```
resource "google_compute_region_url_map" "itaca_url_map" {
  name = "itaca-url-map"
  region = var.region
  default_service = google_compute_region_backend_service.itaca_backend.id
} 
```
#### Output con la ip publica del balanceador
```
output "ip_publica_balanceador" {
  value = google_compute_forwarding_rule.itaca-forwarding-rule.ip_address
}

```
</details>
<br>

## FinOps y Análisis de Costos (Estimación Mensual)
La adopción de la Infraestructura como Código (IaC) permite un despliegue ágil, pero conlleva la responsabilidad de gestionar el presupuesto (FinOps). A continuación, se presenta un desglose de los costos operativos si esta arquitectura se mantuviera encendida 24/7 durante un mes (730 horas) en la región southamerica-west1 (Santiago):

1. Costos Base de Red y Balanceo (Cargos Fijos)
Independientemente de la cantidad de máquinas virtuales que estén funcionando, la infraestructura de red perimetral tiene un costo de mantenimiento constante por hora:
Cloud NAT & Cloud Router: ~ $18.00 USD / mes (Cargo fijo por mantener la pasarela de traducción activa).
Application Load Balancer (Regional): ~ $18.00 USD / mes (Cargo base por las reglas de reenvío y proxy, excluyendo el procesamiento de datos).

**Subtotal Redes: ~ $50.00 USD mensuales.**

2. Costos de Cómputo (Cargos Dinámicos)
El clúster utiliza instancias e2-micro con discos de arranque estándar de 10 GB. El costo por nodo es de aproximadamente $13.00 USD mensuales ($8.00 por cómputo + $5.00 por almacenamiento).
Al tener un Managed Instance Group (MIG) elástico, el costo mensual fluctuará entre dos extremos:
Escenario de Reposo (Tráfico Mínimo): El MIG mantiene 1 sola réplica (min_replicas = 1).
Costo de cómputo: ~ $13.00 USD.

**Costo Total (Redes + Cómputo): ~ $63.00 USD / mes.**

Escenario de Estrés (Pico de Demanda 24/7): El Autoscaler aprovisiona el máximo permitido de 6 réplicas (max_replicas = 6).
Costo de cómputo: ~ $78.00 USD.
**Costo Total (Redes + Cómputo): ~ $114.00 USD / mes.**

### todos estos numeros son estimativos 

Estrategia de Mitigación de Costos
Debido a que este entorno está diseñado con fines de laboratorio y pruebas de resiliencia, el ciclo de vida de la infraestructura es efímero. Al utilizar la inmutabilidad de Terraform, el comando terraform destroy garantiza que no queden recursos huérfanos (como discos desconectados o IPs reservadas).

El costo real de ejecutar el laboratorio completo documentado en este repositorio (despliegue, 15 minutos de estrés al 100% de capacidad y destrucción total) es inferior a $0.10 USD, demostrando un uso altamente eficiente de los recursos de la nube.

## Registro de Incidentes y Resolución de Problemas
### Aprendizajes Principales del Proyecto
- **Alta Disponibilidad:** Configuración y gestión de Managed Instance Groups (MIG) regionales.
- **Métricas y Autoscaling:** Sincronización de tiempos lógicos (Auto-healing vs. Autoscaling) para evitar *flapping* durante el aprovisionamiento de instancias.
- **Networking Avanzado en GCP:** Requisitos obligatorios de topología y subredes dedicadas (Proxy Envoy) para Application Load Balancers modernos.
- **Terraform Avanzado:** Control del ciclo de vida de los recursos y manejo de dependencias implícitas (`depends_on`).
- **Troubleshooting Real:** Depuración de procesos huérfanos en Linux (`nohup`) y resolución de incompatibilidades de ejecución de scripts entre Windows y Linux (CRLF vs LF).
#### Incidente 1 — Inestabilidad en el ciclo de vida del Managed Instance Group (Flapping)

##### Síntoma
Las instancias entraban en un bucle continuo de creación y destrucción, o el autoscaler aprovisionaba réplicas prematuramente antes de registrar tráfico real de usuarios.

##### Causa raíz
La ejecución del startup script (descarga de paquetes vía apt-get e instalación de dependencias de Python) saturaba la CPU de las instancias e2-micro al 100%. El autoscaler interpretaba este pico temporal como tráfico legítimo, mientras que los health checks fallaban al no recibir respuesta en el puerto 8080 debido a que la aplicación aún no estaba inicializada.

##### Resolución implementada
Se diseñó un esquema de desacoplamiento temporal mediante la sincronización de tres variables:
initial_delay_sec = 300 en el MIG — previene que el sistema de auto-healing marque la instancia como corrupta durante los primeros 5 minutos de aprovisionamiento.
cooldown_period = 180 en el autoscaler — instruye al escalador a ignorar los picos de CPU durante los primeros 3 minutos de vida de la instancia.
sleep 300 en el script de inicialización — pospone intencionalmente el proceso de estrés, permitiendo aislar y estabilizar las métricas de arranque frente a las métricas de carga real.

##### Lección aprendida
En instancias pequeñas, la instalación de dependencias genera picos de CPU que el autoscaler no puede distinguir de carga real. Separar la fase de inicialización de la fase de carga es una decisión de diseño. En producción este problema se resuelve usando imágenes de disco pre-construidas (Packer) o contenedores Docker, donde las dependencias ya están instaladas y el arranque toma segundos.

#### Incidente 2 — Fallo silencioso en el aprovisionamiento de instancias (CRLF vs LF)

##### Síntoma
Las instancias se creaban correctamente en Compute Engine pero no exponían la API en el puerto 8080. La verificación de logs en el puerto serie reflejaba que el startup script no se estaba ejecutando.

##### Causa raíz
Incompatibilidad de codificación de caracteres. Al desarrollar el código Terraform en un entorno Windows, se insertaron saltos de línea tipo CRLF (\r\n). El sistema operativo de las instancias (Debian Linux) espera saltos de línea tipo LF (\n), lo que causaba un error de lectura silencioso en el intérprete de bash.

##### Resolución implementada
Estandarización del formato del archivo mediante un comando de sanitización pre-despliegue en PowerShell:
powershell(Get-Content main.tf -Raw) -replace "`r`n", "`n" | Set-Content main.tf -NoNewline

##### Lección aprendida
En entornos Windows, cualquier archivo que contenga scripts bash debe ser normalizado a LF antes de ser procesado por Terraform. La falla es silenciosa: no hay error visible en terraform apply, el problema solo aparece al inspeccionar los logs del puerto serie de la VM.

#### Incidente 3 — Pérdida de enrutamiento en el Application Load Balancer

##### Síntoma
El balanceador retornaba errores de conectividad y los health checks marcaban los backends permanentemente como unhealthy. Adicionalmente el startup script fallaba al intentar actualizar los repositorios de Linux.

##### Causa raíz
Dos problemas simultáneos:
El balanceador regional EXTERNAL_MANAGED opera bajo un esquema de proxies Envoy que requiere por diseño una topología de subred específica que no estaba declarada inicialmente.
Las reglas estrictas de la VPC custom sin IPs públicas bloqueaban tanto el tráfico saliente necesario para la descarga de paquetes como el tráfico entrante de los monitores de Google.

##### Resolución implementada
Topología de red — aprovisionamiento de la subred itaca_proxy con el propósito obligatorio
```
REGIONAL_MANAGED_PROXY:
resource "google_compute_subnetwork" "itaca_proxy" {
  name    = "itaca-subnetwork-proxy"
  region  = var.region
  ip_cidr_range = "10.129.0.0/23"
  network = google_compute_network.itaca_network.id
  purpose = "REGIONAL_MANAGED_PROXY"
  role    = "ACTIVE"
}
```
Salida a internet — despliegue de Cloud NAT y Cloud Router para habilitar tráfico saliente manteniendo el aislamiento de la VPC.
Control de ingress — regla de firewall que autoriza tráfico TCP al puerto 8080 exclusivamente a los rangos IP de los servidores de health check de Google:
source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
##### Lección aprendida
El esquema EXTERNAL_MANAGED es el nuevo estándar para ALB regionales en GCP pero tiene requisitos de red más estrictos que el esquema clásico. La proxy subnet no es opcional, es un prerequisito arquitectónico del balanceador.

#### Incidente 4 — Procesos huérfanos: la API y el script de estrés morían al terminar el startup script

##### Síntoma
La VM arrancaba correctamente e instalaba las dependencias, pero al cabo de unos segundos el health check dejaba de responder. Al conectarse por SSH y ejecutar ps aux, los procesos de uvicorn y stress no estaban corriendo.

##### Causa raíz
El operador & envía el proceso al background pero lo mantiene como hijo del shell actual. Cuando el shell del startup script terminaba, el kernel enviaba SIGHUP a todos los procesos hijos, matándolos.
Código problemático
```
bashpython3 -m uvicorn main:app --host 0.0.0.0 --port 8080 --app-dir /home &
sleep 300 && stress --cpu $(nproc) --timeout 960 &
```
##### Resolución implementada
Uso de nohup para desconectar los procesos del shell padre, combinado con redirección de logs:
```
bashpython3 -m uvicorn main:app --host 0.0.0.0 --port 8080 --app-dir /home &
nohup /home/estresar.sh > /home/estresar.log 2>&1 &
```
El script de estrés fue separado en un archivo independiente con heredoc de comillas simples para evitar interpolación prematura de variables:
```
bashcat > /home/estresar.sh << 'BASH_EOF'
#!/bin/bash
sleep 300
stress --cpu $(nproc) --timeout 960
BASH_EOF
chmod +x /home/estresar.sh
```
##### Lección aprendida
nohup desconecta el proceso del shell padre, permitiendo que sobreviva cuando el shell termina. Las comillas simples en 'BASH_EOF' son críticas: sin ellas bash evaluaría $(nproc) al momento de escribir el archivo en lugar de al momento de ejecutarlo.

#### Incidente 5 — Error en terraform destroy: recurso en uso

##### Síntoma
Al ejecutar terraform destroy, GCP devolvía el siguiente error:
```
Error: googleapi: Error 400: The subnetwork resource 'itaca-subnetwork-proxy' is already being used by 'itaca-forwarding-rule', resourceInUseByAnotherResource
```
La infraestructura quedaba en un estado parcialmente destruido con el state de Terraform desincronizado de GCP.

##### Causa raíz
Terraform intentaba destruir la proxy subnet antes de destruir el forwarding rule. Como el forwarding rule no referenciaba directamente a la proxy subnet en el código, Terraform no infería la dependencia y ejecutaba ambas destrucciones en paralelo.

##### Resolución implementada
Declaración explícita de dependencia mediante depends_on en el forwarding rule:

```
resource "google_compute_forwarding_rule" "itaca-forwarding-rule" {
  name                  = "itaca-forwarding-rule"
  region                = var.region
  target                = google_compute_region_target_http_proxy.itaca_target_proxy.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  network               = google_compute_network.itaca_network.id
  depends_on            = [google_compute_subnetwork.itaca_proxy]
}
```
##### Lección aprendida
Terraform infiere dependencias automáticamente solo cuando hay referencias directas entre recursos. Cuando la dependencia es implícita (dos recursos que GCP relaciona internamente pero que no están referenciados entre sí en el código), hay que declararla explícitamente con depends_on. Esto aplica especialmente al orden de destrucción.

--- 
## colofon - Itaca
durante el documento se lee el nombre "Itaca", Itaca hace alusion al hogar del protagonista de la Iliada de Homero Odiseo (Ὀδυσσεύς) en su nombre griego rey de Itaca donde su amada esposa Penelope(Πηνελόπεια) junto a su hijo Telemaco(Τηλέμαχος) lo esperaban ansiosamente dia a dia, los Romanos como es sabido en la historia tomaron mucho de la cultura griega y lo adaptaron Odiseo se volvio Ulysses, Penelope se volvio Penelopea y Telemaco se volvio Telemachus, todos conocemos la historia de la Iliada, no es lo importane, lo importante de esto es el origen etimologico de la palabra Penelope, este origen se discute, se cree que Pene viene de "hilo, tejido, Trama" por otro lado Florencia viene del Latin, de alguna parte del centro de italia y significa "florida", "en flor" o "aquella que da frutos y florece". esto es importante por que al igual que penelope y odiseo, compartimos una vida de amor juntos, vos y maximo - mi telemaco que al igual que en la historia era solo un bebé cuando esta odisea empezó son mi motor, el hilo con el que hacemos fuerte nuestra Itaca, nuestro hogar de calor, seguridad y felicidad.
