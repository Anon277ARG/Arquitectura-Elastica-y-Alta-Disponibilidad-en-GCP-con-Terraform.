# Arquitectura Elastica y Alta Disponibilidad en GCP con Terraform
## Fase 1 computo y redes
Este repositorio contiene los codigos en terraform para desplegat una arquitectura elastica en Google CLoud Computing (GCP) el diseño esta enfocado en aislar la capa de computo del acceso publico y garantizar el escalado automatico ante picos de demanda.

## objetivos
El objetivo es crear una arquitectura elastica, escalable y funcional

## componentes base de la arquitectura  
-**elasticidad avanzada**implementacion de un Managed Instance Group MIG. con politicas de auto escalado basada en uso de CPU y auto-healing verificados mediante health checks dedicados.<br>
-**distribucion de trafico**configuracion de un aplication load balancer para el balanceo de carga de solicitudes de red.
-**seguridad perimetral**diseño back end 100% aislado en una VPC custom. las instancias carecen de ip publica, con cloud nat para la descarga de actualizaciones de forma segura.

**nota de diseño (Arquitectura stateless)** esta primera version fue diseñada de forma intencional con una arquitectura stateless para enfocarnos unica y puramente en el computo y la arquitectura, en una siguiente version revisaremos las bases de datos y granularidad de datos.

