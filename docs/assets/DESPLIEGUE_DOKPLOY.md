# 🚀 Guía de Despliegue en Dokploy - OpenAdServer v1.0.0 Nettalco

## 📋 Resumen de Cambios

Esta versión incluye:
- ✅ Nueva tabla `app_clients` para gestión de clientes/sistemas
- ✅ Sistema de targeting extendido (app_id, slot, user_role, department, etc.)
- ✅ Middleware de autenticación por API Key
- ✅ CORS configurado
- ✅ Índices optimizados para performance

---

## � Guía de Despliegue (Fresh Install)

**Esta guía realiza un despliegue limpio con base de datos nueva.**

⚠️ **IMPORTANTE:** Se perderán los datos existentes. Si necesitas conservar datos, haz backup primero.

### ✅ Ventajas:
- Base de datos limpia con todas las nuevas tablas
- Sin conflictos de migración
- Más rápido y simple

---

## 📋 Pasos de Despliegue

### Paso 1: Preparar Dokploy

1. **Ir a tu proyecto en Dokploy**
2. **Detener el servicio ad-server** (si está corriendo)
3. **Cambiar el nombre del volumen** en docker-compose.yml:

```yaml
# CAMBIAR DE:
postgres_data_v7:

# A:
postgres_data_v8:   # <-- Incrementar versión
```

4. **Actualizar la referencia en el servicio postgres:**

```yaml
volumes:
  - postgres_data_v8:/var/lib/postgresql/data  # <-- Usar v8
  - ./scripts/init_db.sql:/docker-entrypoint-initdb.d/init.sql:ro
```

### Paso 2: Push de cambios a Git

```bash
git add .
git commit -m "feat: integración Nettalco v1.0.0 - fresh install"
git push origin main
```

### Paso 3: Redesplegar en Dokploy

1. **En Dokploy → Tu proyecto → Settings**
2. **Click en "Redeploy"** (o esperar webhook automático)
3. **Esperar a que se reconstruya** (2-5 minutos)

### Paso 4: Verificar Despliegue

**Ejecutar desde DENTRO del contenedor de PostgreSQL:**

```bash
# 1. Entrar al contenedor postgres
docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash

# 2. Conectarse a la base de datos
psql -U liteads -d liteads

# 3. Verificar tabla app_clients (dentro de psql)
SELECT COUNT(*) FROM app_clients;

# 4. Verificar índices nuevos
SELECT indexname FROM pg_indexes 
WHERE schemaname = 'public' 
  AND indexname LIKE 'idx_targeting%';

# 5. Ver estructura completa de app_clients
\d app_clients

# 6. Ver todas las tablas
\dt

# 7. Salir de psql
\q

# 8. Salir del contenedor
exit
```

**Respuestas esperadas:**
- Paso 3: `count: 0` (tabla vacía pero existe)
- Paso 4: Lista de 4+ índices (idx_targeting_rules_app_id, idx_targeting_rules_slot, etc.)
- Paso 5: Descripción de la tabla con todas las columnas
- Paso 6: Lista completa de tablas (advertisers, campaigns, creatives, app_clients, etc.)

### Paso 5: Crear Cliente API (NECESARIO)

**Desde DENTRO del contenedor de PostgreSQL:**

```bash
# 1. Si no estás dentro del contenedor, entra primero
docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash

# 2. Conectarse a la base de datos
psql -U liteads -d liteads

# 3. Crear cliente Nettalco (dentro de psql)
INSERT INTO app_clients (app_id, api_key, name, company, status)
VALUES (
  'com.nettalco.publicidad',
  'nettalco_' || md5(random()::text),
  'Sistema Nettalco',
  'Nettalco',
  1
) RETURNING app_id, api_key, name;

# 4. Ver el cliente creado
SELECT app_id, api_key, name FROM app_clients;

# 5. Salir
\q
exit
```

**⚠️ IMPORTANTE: Copiar y guardar la API Key que aparece**

**Alternativa: Ejecutar script completo de setup (opcional, para datos de prueba)**

```bash
# Dentro del contenedor bash
cd /tmp
# Si tienes el script en el host, primero cópialo:
# Desde el HOST: docker cp docs/assets/SQL_SETUP_NETTALCO.sql $(docker ps | grep postgres | awk '{print $1}'):/tmp/

# Ejecutar script
psql -U liteads -d liteads -f /tmp/SQL_SETUP_NETTALCO.sql
```

---

## ✅ Verificación Post-Despliegue

### 1. Health Check

```bash
# Desde tu máquina local
curl https://desarrollo.nettalco.com.pe/anunciosNES/health

# Respuesta esperada:
{
  "status": "healthy",
  "version": "x.x.x",
  "timestamp": "..."
}
```

### 2. Test de Endpoint de Anuncios (Sin Auth)

```bash
curl -X POST https://desarrollo.nettalco.com.pe/anunciosNES/api/v1/ad/request \
  -H "Content-Type: application/json" \
  -d '{
    "slot_id": "test_slot",
    "user_id": "test_user",
    "num_ads": 1,
    "device": {
      "os": "web",
      "language": "es"
    }
  }'
```

### 3. Test de Autenticación (Con API Key)

```bash
# Reemplazar TU_API_KEY con la key obtenida
curl -X POST https://desarrollo.nettalco.com.pe/anunciosNES/api/v1/ad/request \
  -H "Content-Type: application/json" \
  -H "X-API-Key: TU_API_KEY" \
  -d '{
    "slot_id": "dashboard_banner_principal",
    "user_id": "000016570",
    "num_ads": 1,
    "device": {
      "os": "web",
      "language": "es"
    },
    "geo": {
      "country": "PE",
      "city": "Lima"
    },
    "context": {
      "app_id": "com.nettalco.publicidad",
      "app_name": "Sistema Publicidad Nettalco"
    },
    "user_features": {
      "custom": {
        "tcodipers": "000016570",
        "cargo": "ANALISTA DE SISTEMAS",
        "unidad_funcional": "SISTEMAS",
        "roles": ["COTIZACIONES_SUPERUSUARIO"],
        "nivel_mas_alto": 150,
        "es_admin": true
      }
    }
  }'
```

**Respuesta esperada exitosa:**
```json
{
  "ads": [
    {
      "ad_id": "...",
      "creative": {
        "title": "...",
        "description": "...",
        "image_url": "...",
        "landing_url": "..."
      },
      "tracking": {
        "impression_url": "...",
        "click_url": "..."
      }
    }
  ],
  "request_id": "..."
}
```

### 4. Test de Nuevo Targeting (Crear Campaña de Prueba)

**Desde DENTRO del contenedor de PostgreSQL:**

```bash
# 1. Entrar al contenedor
docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash

# 2. Conectarse a la base de datos
psql -U liteads -d liteads

# 3. Ejecutar los siguientes comandos SQL uno por uno:
```

**Comandos SQL (copiar y pegar en psql):**

```sql
-- Insertar anunciante
INSERT INTO advertisers (name, company, balance, status) 
VALUES ('Test Advertiser', 'Test Co', 10000.00, 1)
ON CONFLICT DO NOTHING
RETURNING id;

-- Crear campaña (usa el ID del anunciante anterior, o usa 1)
INSERT INTO campaigns (advertiser_id, name, budget_daily, bid_amount, status)
VALUES (1, 'Test Campaign Nettalco', 100.00, 5.00, 1)
RETURNING id;

-- Crear creativo (usa el ID de la campaña anterior, o usa 1)
INSERT INTO creatives (campaign_id, title, description, image_url, landing_url, status)
VALUES (1, 'Test Ad', 'Demo Advertisement', 'https://via.placeholder.com/300x250', 'https://nettalco.com', 1)
RETURNING id;

-- Agregar targeting por app_id
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (1, 'app_id', '{"values": ["com.nettalco.publicidad"]}', true)
RETURNING id;

-- Verificar todo
SELECT 
  c.id as campaign_id,
  c.name as campaign_name,
  COUNT(DISTINCT cr.id) as creatives,
  COUNT(DISTINCT tr.id) as targeting_rules
FROM campaigns c 
LEFT JOIN creatives cr ON cr.campaign_id = c.id
LEFT JOIN targeting_rules tr ON tr.campaign_id = c.id 
WHERE c.id = 1 
GROUP BY c.id, c.name;
```

**Salir:**
```bash
\q
exit
```

### 5. Verificar Logs

```bash
# En Dokploy → Logs → ad-server
# Buscar líneas como:
# "API key validated" - autenticación funcionando
# "Retrieved X candidates from targeting" - targeting funcionando
# "Ad serving completed" - requests exitosos
```

---

## 📊 Monitoreo Post-Despliegue

### Métricas a Vigilar (Primeras 24 horas)

**Desde DENTRO del contenedor de PostgreSQL:**

```bash
# 1. Entrar al contenedor
docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash

# 2. Conectarse a la base de datos
psql -U liteads -d liteads
```

**Consultas SQL (copiar en psql):**

```sql
-- 1. Campañas activas
SELECT 
  c.id,
  c.name,
  c.status,
  COUNT(DISTINCT cr.id) as creatives,
  COUNT(DISTINCT tr.id) as targeting_rules
FROM campaigns c
LEFT JOIN creatives cr ON cr.campaign_id = c.id AND cr.status = 1
LEFT JOIN targeting_rules tr ON tr.campaign_id = c.id
WHERE c.status = 1
GROUP BY c.id, c.name, c.status;

-- 2. Tipos de targeting usados
SELECT 
  rule_type,
  COUNT(*) as count
FROM targeting_rules
GROUP BY rule_type
ORDER BY count DESC;

-- 3. Clientes configurados
SELECT app_id, name, status 
FROM app_clients;

-- 4. Estadísticas de eventos (si hay tráfico)
SELECT 
  event_type,
  COUNT(*) as count,
  DATE(event_time) as day
FROM ad_events
GROUP BY event_type, DATE(event_time)
ORDER BY day DESC, event_type;
```

**Salir:**
```bash
\q
exit
```

---

## 🐛 Troubleshooting

### Error: "relation app_clients does not exist"

**Causa:** La tabla no se creó al inicializar la base de datos

**Solución:**
```bash
# Entrar al contenedor
docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash

# Conectarse a la BD
psql -U liteads -d liteads

# Verificar tablas existentes
\dt

# Si app_clients no existe, crearla manualmente:
CREATE TABLE app_clients (
    id BIGSERIAL PRIMARY KEY,
    app_id VARCHAR(255) UNIQUE NOT NULL,
    api_key VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    company VARCHAR(255),
    allowed_slots JSONB DEFAULT '[]'::jsonb,
    allowed_ips JSONB DEFAULT '[]'::jsonb,
    rate_limit_per_minute INTEGER DEFAULT 1000,
    status SMALLINT DEFAULT 1 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

# Salir
\q
exit
```

### Error: "Invalid API key"

**Causa:** API key incorrecta o cliente inactivo

**Solución:**
```bash
# Entrar al contenedor
docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash
psql -U liteads -d liteads

# Ver API keys válidas (en psql)
SELECT app_id, api_key, name, status 
FROM app_clients 
WHERE status = 1;

# Salir
\q
exit
```

### Error: "No ads returned"

**Causa:** No hay campañas activas o targeting muy restrictivo

**Solución:**
```bash
# Entrar al contenedor
docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash
psql -U liteads -d liteads

# Verificar campañas activas (en psql)
SELECT 
  c.id, 
  c.name, 
  c.status, 
  COUNT(cr.id) as creatives,
  COUNT(tr.id) as targeting_rules
FROM campaigns c
LEFT JOIN creatives cr ON cr.campaign_id = c.id AND cr.status = 1
LEFT JOIN targeting_rules tr ON tr.campaign_id = c.id
WHERE c.status = 1
GROUP BY c.id, c.name, c.status;

# Si no hay campañas, crear una básica:
-- Ver paso "4. Test de Nuevo Targeting" arriba

# Salir
\q
exit
```

### Contenedor no inicia

**Verificar logs:**
```bash
docker logs CONTAINER_NAME --tail 100
```

**Errores comunes:**
- Puerto ya en uso: cambiar puerto en docker-compose.yml
- Volumen corrupto: eliminar volumen y recrear
- Variables de entorno: verificar que estén bien configuradas

---

## 🔒 Configuración de Seguridad (Post-Despliegue)

### 1. Cambiar API Keys de Producción

```bash
# Entrar al contenedor
docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash
psql -U liteads -d liteads

# Actualizar API key (en psql)
UPDATE app_clients 
SET api_key = 'nettalco_prod_' || md5(random()::text || NOW()::text)
WHERE app_id = 'com.nettalco.publicidad';

-- Mostrar nueva key
SELECT app_id, api_key, name FROM app_clients;

# Salir
\q
exit
```

**⚠️ COPIAR Y GUARDAR LA NUEVA API KEY**

### 2. Configurar CORS Específico (Producción)

Editar `liteads/ad_server/main.py`:

```python
if settings.env == "production":
    allowed_origins = [
        "https://publicidad.nettalco.com",
        "https://app.nettalco.com",
    ]
```

Redesplegar.

### 3. Habilitar Autenticación Obligatoria

Editar `liteads/ad_server/middleware/auth.py`:

```python
# Comentar estas líneas:
# if not x_api_key:
#     logger.debug("No API key provided, allowing access")
#     return None

# Descomentar:
if not x_api_key:
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="API key required",
    )
```

---

## 📝 Checklist Final

- [ ] Backup realizado (si migración)
- [ ] Git push completado
- [ ] Dokploy redespliegue exitoso
- [ ] Tabla `app_clients` existe
- [ ] Índices nuevos creados
- [ ] API Key guardada en lugar seguro
- [ ] Health check responde OK
- [ ] Request de anuncio funciona
- [ ] Autenticación funciona (si habilitada)
- [ ] Targeting nuevo funciona
- [ ] Logs sin errores
- [ ] Monitoreo configurado
- [ ] Documentación actualizada
- [ ] Equipo notificado de cambios

---

## 📞 Soporte

**Errores críticos:**

1. **Revisar logs del contenedor:**
   ```bash
   docker logs $(docker ps | grep ad-server | awk '{print $1}') --tail 100
   ```

2. **Verificar base de datos:**
   ```bash
   # Entrar al contenedor postgres
   docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash
   
   # Conectarse
   psql -U liteads -d liteads
   
   # Ver todas las tablas
   \dt
   
   # Ver datos de una tabla
   SELECT * FROM app_clients LIMIT 5;
   
   # Salir
   \q
   exit
   ```

3. **Verificar conectividad:**
   ```bash
   # Desde tu máquina local
   curl https://desarrollo.nettalco.com.pe/anunciosNES/health
   ```

**Documentación:**
- [IMPLEMENTACION_COMPLETADA.md](./IMPLEMENTACION_COMPLETADA.md)
- [INTEGRACION_NETTALCO.md](./INTEGRACION_NETTALCO.md)
- [SQL_SETUP_NETTALCO.sql](./SQL_SETUP_NETTALCO.sql)

---

## 🎯 Próximos Pasos (Opcional)

1. **Configurar Rate Limiting** por API key
2. **Implementar IP Whitelisting** con validación CIDR
3. **Dashboard de monitoreo** con Grafana
4. **Alertas** para errores críticos
5. **Backup automático** diario de PostgreSQL

---

**¡Despliegue completado! 🚀**
