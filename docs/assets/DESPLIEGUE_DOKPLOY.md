# 🚀 Guía de Despliegue en Dokploy - OpenAdServer v1.0.0 Nettalco

## 📋 Resumen de Cambios

Esta versión incluye:
- ✅ Nueva tabla `app_clients` para gestión de clientes/sistemas
- ✅ Sistema de targeting extendido (app_id, slot, user_role, department, etc.)
- ✅ Middleware de autenticación por API Key
- ✅ CORS configurado
- ✅ Índices optimizados para performance

---

## 🔄 Opciones de Despliegue

### Opción 1: FRESH INSTALL (Recomendado para desarrollo)
**Empieza desde cero con base de datos limpia**

**Ventajas:**
- ✅ Base de datos limpia con todas las nuevas tablas
- ✅ Sin conflictos de migración
- ✅ Más rápido y simple

**Desventajas:**
- ❌ **Se pierden todos los datos existentes**
- ❌ Hay que recrear campañas y anunciantes

### Opción 2: MIGRACIÓN (Recomendado para producción)
**Actualiza base de datos existente sin perder datos**

**Ventajas:**
- ✅ Conserva campañas, anunciantes y estadísticas existentes
- ✅ Sin downtime de datos

**Desventajas:**
- ⚠️ Requiere ejecutar script de migración manualmente
- ⚠️ Más pasos

---

## 🆕 OPCIÓN 1: Fresh Install (Base de Datos Nueva)

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

```bash
# Conectarse al contenedor de PostgreSQL
docker exec -it CONTAINER_NAME psql -U liteads -d liteads

# Verificar que existe la nueva tabla
SELECT COUNT(*) FROM app_clients;

# Verificar índices nuevos
SELECT indexname FROM pg_indexes 
WHERE schemaname = 'public' 
  AND indexname LIKE 'idx_targeting%';

# Salir
\q
```

### Paso 5: Ejecutar Script de Setup (Datos de Prueba)

```bash
# Copiar script al contenedor
docker cp docs/assets/SQL_SETUP_NETTALCO.sql POSTGRES_CONTAINER:/tmp/

# Ejecutar
docker exec -it POSTGRES_CONTAINER psql -U liteads -d liteads -f /tmp/SQL_SETUP_NETTALCO.sql

# Ver API Key generada
docker exec -it POSTGRES_CONTAINER psql -U liteads -d liteads -c "SELECT app_id, api_key, name FROM app_clients;"
```

**⚠️ IMPORTANTE: Guardar la API Key que se muestra**

---

## 🔄 OPCIÓN 2: Migración (Conservar Datos Existentes)

### Paso 1: Backup de Seguridad

```bash
# Conectar al servidor Dokploy
ssh usuario@tu-servidor-dokploy

# Crear backup
docker exec POSTGRES_CONTAINER pg_dump -U liteads liteads > backup_pre_migracion_$(date +%Y%m%d_%H%M%S).sql

# Verificar backup
ls -lh backup_pre_migracion_*.sql
```

### Paso 2: Push de cambios a Git

```bash
git add .
git commit -m "feat: integración Nettalco v1.0.0 - migración"
git push origin main
```

### Paso 3: Ejecutar Script de Migración

```bash
# En el servidor Dokploy

# Copiar script de migración al contenedor
docker cp scripts/migration_nettalco_v1.sql POSTGRES_CONTAINER:/tmp/

# Ejecutar migración
docker exec -it POSTGRES_CONTAINER psql -U liteads -d liteads -f /tmp/migration_nettalco_v1.sql
```

**Salida esperada:**
```
============================================================
Migración completada exitosamente!
============================================================
App Clients creados: 1
Índices de targeting creados: 4

⚠️  IMPORTANTE: Guardar esta API Key:
API Key Nettalco: nettalco_dev_XXXXXXXXXXXX
```

### Paso 4: Reiniciar Servicios en Dokploy

1. **Dokploy → Tu proyecto → Actions**
2. **Click en "Restart"**
3. **Esperar 30-60 segundos**

### Paso 5: Verificar Migración

```bash
# Verificar tabla app_clients
docker exec POSTGRES_CONTAINER psql -U liteads -d liteads -c "SELECT * FROM app_clients;"

# Verificar nuevos índices
docker exec POSTGRES_CONTAINER psql -U liteads -d liteads -c "
  SELECT indexname, tablename 
  FROM pg_indexes 
  WHERE schemaname = 'public' 
    AND indexname LIKE 'idx_targeting_rules_%';
"

# Verificar función helper
docker exec POSTGRES_CONTAINER psql -U liteads -d liteads -c "
  SELECT proname, prosrc 
  FROM pg_proc 
  WHERE proname = 'validate_api_key';
"
```

---

## ✅ Verificación Post-Despliegue (Ambas Opciones)

### 1. Health Check

```bash
# Desde tu máquina local
curl https://tu-dominio.com/anunciosNES/health

# Respuesta esperada:
{
  "status": "healthy",
  "version": "x.x.x",
  "timestamp": "..."
}
```

### 2. Test de Endpoint de Anuncios (Sin Auth)

```bash
curl -X POST https://tu-dominio.com/anunciosNES/api/v1/ad/request \
  -H "Content-Type: application/json" \
  -d '{
    "slot_id": "test_slot",
    "user_id": "test_user",
    "num_ads": 1
  }'
```

### 3. Test de Autenticación (Con API Key)

```bash
# Reemplazar TU_API_KEY con la key obtenida
curl -X POST https://tu-dominio.com/anunciosNES/api/v1/ad/request \
  -H "Content-Type: application/json" \
  -H "X-API-Key: TU_API_KEY" \
  -d '{
    "slot_id": "dashboard_banner_principal",
    "user_id": "000016570",
    "num_ads": 1,
    "context": {
      "app_id": "com.nettalco.publicidad",
      "app_name": "Sistema Publicidad Nettalco"
    }
  }'
```

### 4. Test de Nuevo Targeting

```bash
# Crear campaña de prueba con nuevo targeting
docker exec POSTGRES_CONTAINER psql -U liteads -d liteads -c "
  -- Insertar anunciante si no existe
  INSERT INTO advertisers (name, company, balance, status) 
  SELECT 'Test Advertiser', 'Test Co', 10000.00, 1
  WHERE NOT EXISTS (SELECT 1 FROM advertisers WHERE company = 'Test Co')
  RETURNING id;
  
  -- Crear campaña (reemplazar ADVERTISER_ID con el ID obtenido)
  INSERT INTO campaigns (advertiser_id, name, budget_daily, bid_amount, status)
  VALUES (1, 'Test Campaign Nettalco', 100.00, 5.00, 1)
  RETURNING id;
  
  -- Agregar targeting por app_id (reemplazar CAMPAIGN_ID)
  INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
  VALUES (1, 'app_id', '{\"values\": [\"com.nettalco.publicidad\"]}', true);
"
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

```bash
# Estadísticas de uso
docker exec POSTGRES_CONTAINER psql -U liteads -d liteads -c "
  SELECT 
    app_id,
    name as sistema,
    COUNT(*) as requests
  FROM app_clients ac
  LEFT JOIN ad_events ae ON ae.user_id LIKE ac.app_id || '%'
  GROUP BY app_id, name;
"

# Campañas activas
docker exec POSTGRES_CONTAINER psql -U liteads -d liteads -c "
  SELECT 
    c.name,
    COUNT(DISTINCT cr.id) as creatives,
    COUNT(DISTINCT tr.id) as targeting_rules
  FROM campaigns c
  LEFT JOIN creatives cr ON cr.campaign_id = c.id AND cr.status = 1
  LEFT JOIN targeting_rules tr ON tr.campaign_id = c.id
  WHERE c.status = 1
  GROUP BY c.id, c.name;
"

# Tipos de targeting usados
docker exec POSTGRES_CONTAINER psql -U liteads -d liteads -c "
  SELECT 
    rule_type,
    COUNT(*) as count
  FROM targeting_rules
  GROUP BY rule_type
  ORDER BY count DESC;
"
```

---

## 🐛 Troubleshooting

### Error: "relation app_clients does not exist"

**Causa:** Migración no se ejecutó o falló

**Solución:**
```bash
docker exec POSTGRES_CONTAINER psql -U liteads -d liteads -f /tmp/migration_nettalco_v1.sql
```

### Error: "Invalid API key"

**Causa:** API key incorrecta o cliente inactivo

**Solución:**
```bash
# Ver API keys válidas
docker exec POSTGRES_CONTAINER psql -U liteads -d liteads -c "
  SELECT app_id, api_key, status 
  FROM app_clients 
  WHERE status = 1;
"
```

### Error: "No ads returned"

**Causa:** No hay campañas activas o targeting muy restrictivo

**Solución:**
```bash
# Verificar campañas activas
docker exec POSTGRES_CONTAINER psql -U liteads -d liteads -c "
  SELECT c.id, c.name, c.status, COUNT(cr.id) as creatives
  FROM campaigns c
  LEFT JOIN creatives cr ON cr.campaign_id = c.id AND cr.status = 1
  WHERE c.status = 1
  GROUP BY c.id;
"

# Ejecutar SQL_SETUP_NETTALCO.sql para crear datos de prueba
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
docker exec POSTGRES_CONTAINER psql -U liteads -d liteads -c "
  UPDATE app_clients 
  SET api_key = 'nettalco_prod_' || md5(random()::text || NOW()::text)
  WHERE app_id = 'com.nettalco.publicidad';
  
  -- Mostrar nueva key
  SELECT app_id, api_key FROM app_clients;
"
```

**⚠️ GUARDAR LA NUEVA API KEY**

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
1. Revisar logs: `docker logs CONTAINER_NAME`
2. Verificar base de datos: `docker exec -it POSTGRES_CONTAINER psql -U liteads`
3. Rollback si es necesario: restaurar backup

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
