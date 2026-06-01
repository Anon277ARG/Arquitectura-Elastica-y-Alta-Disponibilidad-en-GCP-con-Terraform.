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
- durante el documento se leera el nombre "Itaca", Itaca hace alusion al hogar del protagonista de la Iliada de Homero Odiseo (Ὀδυσσεύς) en su nombre griego rey de Itaca donde su amada esposa Penelope(Πηνελόπεια) junto a su hijo Telemaco(Τηλέμαχος) lo esperaban ansiosamente dia a dia, los Romanos como es sabido en la historia tomaron mucho de la cultura griega y lo adaptaron Odiseo se volvio Ulysses, Penelope se volvio Penelopea y Telemaco se volvio Telemachus, lo importante de esto es que si bien el origen etimologico de la palabra Penelope se discute, se cree que Pene viene "hilo, tejido, Trama" por otro lado Florencia viene del Latin de alguna parte del centro de italia y significa "florida", "en flor" o "aquella que da frutos y florece". esto es importante por que como penelope y odiseo compartimos una vida de amor juntos, sos mi motor.

### componentes de la arquitectura actual
- Load Balancer funciona como acceso publico a nuestra red.
- firewall con sus correspondientes tags
- red VPC donde vive toda nuestra arquitectura.
- Sub red proxy para garantizar el funcionamiento de el load balancer.
- Subnet donde viven nuestras VMs.
- Manage instance group para el control de las VMs.
- instance template para la creacion de las VMs
- autoscaler con politicas de uso de cpu
- auto healing
- cloud router para garantizar el funcionamiento del cloud nat
- cloud nat para garantizar que las nuevas VMs tengan todas las dependencias necesarias para funciona.

## Componentes

### redes
- red VPC privada con el nombre de "itaca-network" creada en Santiago, la unica configuracion relevante aca es que se desactivo la creacion automatica de subredes
- 

