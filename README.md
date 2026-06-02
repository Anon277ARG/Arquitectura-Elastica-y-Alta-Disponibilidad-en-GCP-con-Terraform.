# Arquitectura Elastica y Alta Disponibilidad en GCP con Terraform
## Fase 1 computo y redes
Este repositorio contiene los codigos en terraform para desplegar una arquitectura elastica en Google CLoud Computing (GCP) el diseño esta enfocado en aislar la capa de computo del acceso publico y garantizar el escalado automatico ante picos de demanda.

## objetivos
El objetivo es crear una arquitectura elastica, escalable y funcional

## componentes base de la arquitectura  
- **elasticidad avanzada** implementacion de un Managed Instance Group MIG. con politicas de auto escalado basada en uso de CPU y auto-healing verificados mediante health checks dedicados.<br>
- **distribucion de trafico** configuracion de un aplication load balancer para el balanceo de carga de solicitudes de red.<br>
- **seguridad perimetral** diseño back end 100% aislado en una VPC custom. las instancias carecen de ip publica, con cloud nat para la descarga de actualizaciones de forma segura.<br>

### notas de diseño (Arquitectura stateless)
- esta primera version fue diseñada de forma intencional con una arquitectura stateless para enfocarnos unica y puramente en el computo y la arquitectura, en una siguiente version revisaremos las bases de datos y granularidad de datos.
- durante el documento se leera el nombre "Itaca", Itaca hace alusion al hogar del protagonista de la Iliada de Homero Odiseo (Ὀδυσσεύς) en su nombre griego rey de Itaca donde su amada esposa Penelope(Πηνελόπεια) junto a su hijo Telemaco(Τηλέμαχος) lo esperaban ansiosamente dia a dia, los Romanos como es sabido en la historia tomaron mucho de la cultura griega y lo adaptaron Odiseo se volvio Ulysses, Penelope se volvio Penelopea y Telemaco se volvio Telemachus, todos conocemos la historia de la Iliada, no es lo importane, lo importante de esto es el origen etimologico de la palabra Penelope, este origen se discute, se cree que Pene viene "hilo, tejido, Trama" por otro lado Florencia viene del Latin, de alguna parte del centro de italia y significa "florida", "en flor" o "aquella que da frutos y florece". esto es importante por que al igual que penelope y odiseo, compartimos una vida de amor juntos, vos y maximo - mi telemaco que al igual que en la historia era solo un bebé cuando esta odisea empezó son mi motor, el hilo con el que hacemos fuerte nuestra Itaca, nuestro hogar de calor, seguridad y felicidad.

## Diagrama de arquitectura visual

  

### requisitos
- **cuenta de Google Cloud Computing GCP** - un proyecto de GCP creado y activo, cuenta de facturacion (BIlling) vinculada al proyecto.
- **APIs Habilitadas** - la api de compute engine habilitada en el proyecto.
- **Herramientas de linea de comandos (CLI) y terraform** - terraform instalado en tu entorno local, Gcloud instalado y autenticado.
- **Permisos de IAM** - tener los permisos en GCP para crear redes y maquinas virtuales.

### despliegue
1. Clonar el repositorio: git clone https://github.com/tu-usuario/tu-repo.git
2. autenticar en gcp: gcloud auth application-default login
3. Configurar el proyecto: gcloud config set project cloud-lab-493
4. iniciar terraform: terraform init
5. verificar los cambios antes de aplicar: terraform plan
6. aplicar la infraestructura: terraform apply
7. Obetener la ip del load blancer: terraform output ip_publica_balanceador
8. Destruir el entorno cuando termine: terraform destroy
   
## Componentes

### redes
- red VPC privada con el nombre de "itaca-network" creada en Santiago, la unica configuracion relevante aca es que se desactivo la creacion automatica de subredes.
- sub red con el nombre de "Itaca-subnet" dedicada a asegurar la privacidad de las VMs.
- sub red proxy para asegurar la conexion entre el Load Balancer y la sub red de las VMs.
- cloud router para el ruteo a la internet publica
- cloud nat para la traduccion de ips

### Firewall
- reglas de firewall con el nombre "itaca-firewall, itaca-health-check, allow-ssh-itaca"
- todas las reglas con el mismo tag para evitar confuciones "itaca-firewalls"
**abieros los puertos y las ips**
- "22 y 35.235.240.0/20" para la conexions ssh
- "8080 y 10.129.0.0/23" para la conexion del proxy con el load balancer
- "8080 y 35.191.0.0/16, 130.211.0.0/22" para los health check

### BackEnds
#### MAnage Intance Group con la siguiente configuracion
- con el nombre "itaca-mig
- conectado al puerto 8080
- configurado en la region santiago
- initial delay de 300 segundos de delay como health check policy, para que las VMs se pongan en linea.
### mig template con la siguiente configuracion
- nombre: virtual-machine-template
- tag: "itaca-firewalls" para llamar a todos los firewalls
- instancia: e2-Micro, no es necesario mas.
- bloqueo de enrutamiento no autorizado para que las instancias actuen como nodos finales.
- con la imagen de Debian 11
- con la interfaz de red de itaca Network viviendo dentro de Itaca Subnet.
- en la parte de meta data como Startup script que despliega la API para responder inmediatamente a los health checks, y lanza un proceso en segundo plano que, tras 300 segundos de delay, estresa la CPU al 100% para detonar el autoscaling, esto se definio asi ya que la instancia es una e2-Micro y al instalar las dependencias sube el uso de la CPU al 100% activando el autoscaler.
**autoscaler con la siguiente configuracion**
- nombre: "autoscaler-itaca"
- politica de autoscaling como 1 en replicas minimas y 6 en replicas maximas
- un cooldown period de 180 segundos para asegurarnos la no creacion de replicas indeseadas.
- como politica de replicacion se configuro uso de CPU al 80%.
**servicio Back end con la siguiente configuracion**
- nombre: "itaca-backend-service"
- protocolo: HTTP
- esquema de balanceo de carga como "External Managed" usando el nuevo esquema y dandole sentido a la subnet proxy
- modo de Balanceo configurado en "Utilization" en base al uso
- capacidad de scaler en 1.0
