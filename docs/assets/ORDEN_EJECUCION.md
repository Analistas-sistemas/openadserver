# 📋 Orden Correcto de Ejecución - OpenAdServer Nettalco

## ✅ ORDEN DE SCRIPTS (PASO A PASO)

### 🔹 FASE 1: Preparación Local

#### 1. Hacer commit de las correcciones

```bash
cd "d:\PROYECTOS NETTALCO\OTROS\OPENADSERVER\openadserver"

git add .
git commit -m "fix: corregir schema de base de datos (eliminar quality_score, impressions, clicks, conversions de modelos)"
git push origin main
```

---

### 🔹 FASE 2: Configuración Dokploy

#### 2. Cambiar volumen de PostgreSQL (Base de datos NUEVA)

**En tu editor local**, abrir `docker-compose.yml` y cambiar:

```yaml
volumes:
  postgres_data_v9:  # <-- CAMBIAR de v8 a v9 (o el número que sigue)

services:
  postgres:
    volumes:
      - postgres_data_v9:/var/lib/postgresql/data  # <-- Actualizar aquí también
```

#### 3. Hacer commit del cambio de volumen

```bash
git add docker-compose.yml
git commit -m "chore: cambiar a postgres_data_v9 para fresh install"
git push origin main
```

---

### 🔹 FASE 3: Despliegue

#### 4. Redesplegar en Dokploy

1. **Ir a Dokploy** → Tu proyecto
2. **Click en "Redeploy"** o esperar webhook automático
3. **Esperar 2-5 minutos** hasta que termine

---

### 🔹 FASE 4: Verificación Base de Datos

#### 5. Entrar al contenedor PostgreSQL

```bash
# Desde tu máquina local (SSH a servidor Dokploy)
docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash
```

#### 6. Conectarse a la base de datos

```bash
# Dentro del contenedor
psql -U liteads -d liteads
```

#### 7. Verificar tablas creadas (DENTRO de psql)

```sql
-- Ver todas las tablas
\dt

-- Debe mostrar:
-- advertisers
-- app_clients       <-- ⭐ NUEVA
-- campaigns
-- creatives
-- targeting_rules
-- ad_events
-- hourly_stats
```

#### 8. Verificar estructura de creatives (DENTRO de psql)

```sql
-- Ver columnas de creatives
\d creatives

-- NO DEBE TENER: quality_score, impressions, clicks, conversions
-- DEBE TENER: id, campaign_id, title, description, image_url, video_url, landing_url, creative_type, width, height, status, created_at, updated_at
```

#### 9. Verificar estructura de campaigns (DENTRO de psql)

```sql
-- Ver columnas de campaigns
\d campaigns

-- NO DEBE TENER: impressions, clicks, conversions
-- DEBE TENER: id, advertiser_id, name, description, budget_daily, budget_total, spent_today, spent_total, bid_type, bid_amount, start_time, end_time, freq_cap_daily, freq_cap_hourly, status, created_at, updated_at
```

#### 10. Verificar datos demo creados (DENTRO de psql)

```sql
-- Ver advertiser demo
SELECT * FROM advertisers;

-- Ver campaign demo
SELECT * FROM campaigns;

-- Ver creative demo
SELECT * FROM creatives;
```

**Si TODO está bien, continuar. Si NO, revisar logs de Docker.**

---

### 🔹 FASE 5: Configuración Nettalco (SCRIPTS SQL)

#### 11. Salir de psql pero quedarse en contenedor

```bash
# Dentro de psql
\q

# Ahora estás en bash del contenedor
```

#### 12. Copiar script SQL_SETUP_NETTALCO.sql al contenedor

**Desde TU MÁQUINA (otra terminal):**

```bash
# Copiar archivo al contenedor
docker cp "d:\PROYECTOS NETTALCO\OTROS\OPENADSERVER\openadserver\docs\assets\SQL_SETUP_NETTALCO.sql" $(docker ps | grep postgres | awk '{print $1}'):/tmp/
```

#### 13. Ejecutar script de configuración Nettalco

**Volver al contenedor (donde estabas en bash):**

```bash
# Ejecutar script completo
psql -U liteads -d liteads -f /tmp/SQL_SETUP_NETTALCO.sql
```

**Este script crea:**
- ✅ Tabla `app_clients` (si no existía)
- ✅ Cliente Nettalco con API key
- ✅ Anunciante de prueba
- ✅ Campaña de prueba
- ✅ 2 creativos
- ✅ Targeting rules (app_id, slot, geo)
- ✅ Índices optimizados
- ✅ Función de validación
- ✅ Vista de monitoreo

#### 14. Copiar API Key generada

**Dentro del contenedor, ejecutar:**

```bash
# Conectarse nuevamente
psql -U liteads -d liteads

# Copiar esta API Key (DENTRO de psql)
SELECT app_id, api_key, name FROM app_clients WHERE app_id = 'com.nettalco.publicidad';

-- COPIAR Y GUARDAR LA API KEY QUE APARECE
```

**Ejemplo de salida:**
```
            app_id            |              api_key               |            name
------------------------------+------------------------------------+---------------------------
 com.nettalco.publicidad      | nettalco_api_key_abc123def456...   | Sistema Publicidad Nettalco
```

**⚠️ IMPORTANTE: GUARDAR LA API KEY EN TU GESTOR DE CONTRASEÑAS**

#### 15. Verificar configuración completa (DENTRO de psql)

```sql
-- Ver campaña creada
SELECT 
    c.id as campaign_id,
    c.name as campaign_name,
    a.name as advertiser_name,
    COUNT(DISTINCT cr.id) as num_creatives,
    COUNT(DISTINCT tr.id) as num_targeting_rules,
    c.bid_type,
    c.bid_amount,
    c.status
FROM campaigns c
JOIN advertisers a ON c.advertiser_id = a.id
LEFT JOIN creatives cr ON cr.campaign_id = c.id AND cr.status = 1
LEFT JOIN targeting_rules tr ON tr.campaign_id = c.id
WHERE c.name LIKE '%Nettalco%'
GROUP BY c.id, c.name, a.name, c.bid_type, c.bid_amount, c.status;

-- Debe mostrar:
-- campaign_id: 2 (o mayor)
-- num_creatives: 2
-- num_targeting_rules: 3
```

#### 16. Salir del contenedor

```sql
-- Dentro de psql
\q
```

```bash
# Dentro del contenedor bash
exit
```

---

### 🔹 FASE 6: Pruebas Funcionales

#### 17. Test Health Check

**Desde tu máquina local:**

```bash
curl https://desarrollo.nettalco.com.pe/anunciosNES/health
```

**Respuesta esperada:**
```json
{
  "status": "healthy",
  "version": "x.x.x",
  "timestamp": "..."
}
```

#### 18. Test Request de Anuncios (SIN API Key)

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

**Respuesta esperada:**
```json
{
  "ads": [],
  "request_id": "..."
}
```

**O puede devolver el anuncio demo si coincide con el targeting.**

#### 19. Test Request CON API Key y Targeting Nettalco

**Reemplazar `TU_API_KEY_AQUI` con la API key del paso 14:**

```bash
curl -X POST https://desarrollo.nettalco.com.pe/anunciosNES/api/v1/ad/request \
  -H "Content-Type: application/json" \
  -H "X-API-Key: TU_API_KEY_AQUI" \
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

**Respuesta esperada (con anuncio):**
```json
{
  "ads": [
    {
      "ad_id": "req_xxxxx_2_y",
      "creative": {
        "title": "Oferta Especial Nettalco",
        "description": "¡Descuento del 30% en todos nuestros servicios!",
        "image_url": "https://via.placeholder.com/300x250?text=Nettalco+Offer",
        "landing_url": "https://www.nettalco.com/ofertas",
        "width": 300,
        "height": 250
      },
      "tracking": {
        "impression_url": "https://desarrollo.nettalco.com.pe/anunciosNES/api/v1/event/impression?request_id=req_xxxxx&ad_id=req_xxxxx_2_y",
        "click_url": "https://desarrollo.nettalco.com.pe/anunciosNES/api/v1/event/click?request_id=req_xxxxx&ad_id=req_xxxxx_2_y"
      }
    }
  ],
  "request_id": "req_xxxxx"
}
```

---

### 🔹 FASE 7: Verificación Final

#### 20. Revisar logs de la aplicación

**En Dokploy:**

1. Ir a **Logs** → `ad-server`
2. Buscar líneas recientes:
   - `"Ad serving completed"` ✅
   - `"Retrieved X candidates from targeting"` ✅
   - **NO debe haber** errores tipo `column X does not exist` ❌

#### 21. Revisar logs de PostgreSQL

```bash
docker logs $(docker ps | grep postgres | awk '{print $1}') --tail 50
```

**Buscar:**
- `"LiteAds database initialized successfully!"` ✅
- **NO debe haber** errores SQL ❌

---

## 📊 RESUMEN DE SCRIPTS EJECUTADOS

### Scripts ejecutados AUTOMÁTICAMENTE (por Docker):

1. **`scripts/init_db.sql`** 
   - Se ejecuta automáticamente al crear el contenedor
   - Crea todas las tablas base
   - Inserta datos demo básicos
   - Crea índices iniciales

### Scripts ejecutados MANUALMENTE (por ti):

2. **`docs/assets/SQL_SETUP_NETTALCO.sql`**
   - Lo ejecutas desde dentro del contenedor PostgreSQL
   - Configura cliente Nettalco
   - Crea campaña de prueba específica
   - Agrega índices adicionales
   - Crea funciones y vistas de monitoreo

---

## 🎯 CHECKLIST FINAL

- [ ] Código pushed a Git (paso 1 y 3)
- [ ] Volumen cambiado a `postgres_data_v9` (paso 2)
- [ ] Redespliegue completado (paso 4)
- [ ] Tablas verificadas (paso 7)
- [ ] Estructura de `creatives` correcta - SIN quality_score/impressions/clicks/conversions (paso 8)
- [ ] Estructura de `campaigns` correcta - SIN impressions/clicks/conversions (paso 9)
- [ ] Datos demo existen (paso 10)
- [ ] Script `SQL_SETUP_NETTALCO.sql` ejecutado (paso 13)
- [ ] API Key guardada (paso 14)
- [ ] Campaña Nettalco creada (paso 15)
- [ ] Health check funciona (paso 17)
- [ ] Request sin auth funciona (paso 18)
- [ ] Request con auth funciona (paso 19)
- [ ] Logs sin errores (paso 20 y 21)

---

## 🚨 Troubleshooting

### Error: "column creatives.quality_score does not exist"

**Causa:** El modelo Python tiene un campo que la tabla SQL no tiene.

**Solución:** Ya fue corregido en el paso 1. Verificar que el código esté actualizado:

```bash
git pull origin main
```

### Error: "relation app_clients does not exist"

**Causa:** El script `init_db.sql` no se ejecutó o falló.

**Solución:**

```bash
# Entrar al contenedor
docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash

# Ejecutar manualmente
psql -U liteads -d liteads < /docker-entrypoint-initdb.d/init.sql

# O recrear la tabla manualmente (dentro de psql)
psql -U liteads -d liteads
CREATE TABLE app_clients ( ... );  # Ver estructura en init_db.sql
```

### Error: "No ads returned" pero esperabas anuncios

**Causa:** El targeting no coincide con el request.

**Solución:** Verificar targeting rules:

```bash
docker exec -it $(docker ps | grep postgres | awk '{print $1}') bash
psql -U liteads -d liteads

# Ver targeting de la campaña
SELECT tr.rule_type, tr.rule_value, tr.is_include
FROM targeting_rules tr
JOIN campaigns c ON c.id = tr.campaign_id
WHERE c.name LIKE '%Nettalco%';

# Verificar que el request incluya los valores correctos:
# - app_id: "com.nettalco.publicidad"
# - slot: "dashboard_banner_principal" o "dashboard_sidebar_top"
# - geo.country: "PE"
```

---

## 📞 Soporte

**Si todo falló:**

1. **Destruir volumen y empezar de cero:**

```bash
# Detener contenedores
docker-compose down

# Eliminar volumen
docker volume rm openadserver_postgres_data_v9

# Volver a desplegar
# (El init_db.sql se ejecutará automáticamente)
```

2. **Revisar logs completos:**

```bash
# Logs de aplicación
docker logs $(docker ps | grep ad-server | awk '{print $1}') --tail 200

# Logs de base de datos
docker logs $(docker ps | grep postgres | awk '{print $1}') --tail 200
```

3. **Verificar variables de entorno:**

```bash
docker exec $(docker ps | grep ad-server | awk '{print $1}') env | grep -E "DATABASE|REDIS|ENV"
```

---

**¡Éxito en tu despliegue! 🚀**
