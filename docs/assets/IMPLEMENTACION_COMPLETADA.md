# Implementación Completa - OpenAdServer para Nettalco

## 📋 Resumen de Cambios Implementados

Se ha completado la integración de OpenAdServer con el sistema Nettalco, agregando todas las funcionalidades necesarias para servir anuncios a usuarios internos de la empresa.

---

## ✅ Funcionalidades Implementadas

### 1. **Extención de UserContext** 
📁 `liteads/schemas/internal.py`

- ✅ Agregado campo `slot_id` para identificar la ubicación del anuncio
- ✅ Campo `custom_features` ya existente para características personalizadas de usuarios

```python
@dataclass
class UserContext:
    # ... campos existentes ...
    slot_id: str = ""  # ⭐ NUEVO
    custom_features: dict[str, Any] = field(default_factory=dict)
```

### 2. **Sistema de Targeting Extendido**
📁 `liteads/rec_engine/retrieval/targeting.py`

Se agregaron **6 nuevos tipos de reglas de targeting**:

| Rule Type | Descripción | Ejemplo de Uso |
|-----------|-------------|----------------|
| `app_id` | Filtrar por app/sistema específico | Mostrar solo en sistema Nettalco |
| `slot` | Filtrar por ubicación del anuncio | Solo en sidebar_top |
| `user_role` | Filtrar por roles de usuario | Solo para COMERCIAL_JEFE |
| `department` | Filtrar por departamento | Solo para SISTEMAS |
| `permission_level` | Filtrar por nivel de permisos | Solo nivel >= 100 |
| `is_admin` | Filtrar por administradores | Solo superusuarios |

**Ejemplos de configuración:**

```sql
-- Solo para sistema Nettalco
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (1, 'app_id', '{"values": ["com.nettalco.publicidad"]}'::jsonb, true);

-- Solo en slots específicos
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (1, 'slot', '{"values": ["dashboard_banner_principal"]}'::jsonb, true);

-- Solo para jefes
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (1, 'user_role', '{"roles": ["COMERCIAL_JEFE", "COTIZACIONES_SUPERUSUARIO"]}'::jsonb, true);
```

### 3. **Modelo AppClient para Gestión de Clientes**
📁 `liteads/models/ad.py`

- ✅ Nuevo modelo `AppClient` para gestionar sistemas externos
- ✅ Campos: `app_id`, `api_key`, `name`, `company`, `allowed_slots`, `allowed_ips`, `rate_limit_per_minute`
- ✅ Integrado con SQLAlchemy ORM
- ✅ Exportado en `liteads/models/__init__.py`

```python
class AppClient(Base, TimestampMixin):
    """App clients / external systems allowed to use the ad server."""
    
    app_id: str  # Identificador único del sistema
    api_key: str  # API key para autenticación
    name: str  # Nombre descriptivo
    allowed_slots: list[str] | None  # Slots permitidos
    allowed_ips: list[str] | None  # IPs permitidas (CIDR)
    rate_limit_per_minute: int  # Límite de requests
```

### 4. **Middleware de Autenticación**
📁 `liteads/ad_server/middleware/auth.py` (NUEVO)

- ✅ Validación de API Key mediante header `X-API-Key`
- ✅ Consulta a base de datos para verificar cliente
- ✅ Soporte para IP whitelisting (preparado, no implementado aún)
- ✅ **Backwards compatible**: permite acceso sin API Key por defecto

**Cómo usar:**

```python
from liteads.ad_server.middleware.auth import verify_api_key, require_api_key
from fastapi import Depends

# Opción 1: Opcional (compatible con versiones anteriores)
@router.post("/request")
async def request_ads(
    app_client = Depends(verify_api_key)  # Puede ser None
):
    pass

# Opción 2: Requerido
@router.post("/secure-endpoint", dependencies=[Depends(require_api_key)])
async def secure_endpoint():
    pass
```

### 5. **Schema de Base de Datos Actualizado**
📁 `scripts/init_db.sql`

- ✅ Tabla `app_clients` agregada con todos los campos necesarios
- ✅ Índices optimizados para `app_id`, `api_key`, `status`
- ✅ Índices JSONB para targeting rules (`app_id`, `slot`, `user_role`, `department`)

**Ejecutar migración:**

```bash
# Opción 1: Recrear base de datos (DESARROLLO)
docker-compose down -v
docker-compose up -d

# Opción 2: Ejecutar solo la migración (PRODUCCIÓN)
psql -h localhost -U postgres -d liteads < scripts/init_db.sql
```

### 6. **CORS Configurado**
📁 `liteads/ad_server/main.py`

- ✅ Headers permitidos: `Content-Type`, `X-API-Key`, `Authorization`
- ✅ Métodos permitidos: `GET`, `POST`, `OPTIONS`
- ✅ Headers expuestos: `X-Request-ID`, `X-Response-Time`
- ✅ Preparado para configuración específica de producción

**Configuración para producción:**

```python
if settings.env == "production":
    allowed_origins = [
        "https://publicidad.nettalco.com",
        "https://app.nettalco.com",
    ]
```

### 7. **Construcción de UserContext Mejorada**
📁 `liteads/ad_server/services/ad_service.py`

- ✅ `slot_id` se extrae automáticamente del `AdRequest`
- ✅ `custom_features` se pasa desde `request.user_features.custom`

---

## 🚀 Cómo Usar las Nuevas Funcionalidades

### 1. Configurar Cliente en Base de Datos

Ejecutar el script `docs/assets/SQL_SETUP_NETTALCO.sql`:

```bash
psql -h localhost -U postgres -d liteads < docs/assets/SQL_SETUP_NETTALCO.sql
```

Esto creará:
- Cliente Nettalco con API key
- Campañas de prueba
- Targeting rules de ejemplo

**Obtener la API Key generada:**

```sql
SELECT app_id, api_key, name 
FROM app_clients 
WHERE app_id = 'com.nettalco.publicidad';
```

### 2. Request de Anuncio (Con Autenticación)

```bash
curl -X POST http://localhost:8000/api/v1/ad/request \
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
      "country": "PE"
    },
    "context": {
      "app_id": "com.nettalco.publicidad",
      "app_name": "Sistema Publicidad Nettalco"
    },
    "user_features": {
      "custom": {
        "tcodipers": "000016570",
        "cargo": "ANALISTA DE SISTEMAS JUNIOR",
        "unidad_funcional": "SISTEMAS",
        "roles": ["COTIZACIONES_SUPERUSUARIO"],
        "nivel_mas_alto": 150,
        "es_admin": true
      }
    }
  }'
```

### 3. Request Sin Autenticación (Backwards Compatible)

```bash
curl -X POST http://localhost:8000/api/v1/ad/request \
  -H "Content-Type: application/json" \
  -d '{
    "slot_id": "dashboard_banner_principal",
    "user_id": "test_user",
    "num_ads": 1
  }'
```

### 4. Crear Campaña con Targeting Específico

```sql
-- 1. Crear campaña
INSERT INTO campaigns (advertiser_id, name, budget_daily, bid_amount, status)
VALUES (1, 'Campaña Solo Jefes', 500.00, 3.50, 1)
RETURNING id;

-- 2. Agregar targeting por app_id
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (CAMPAIGN_ID, 'app_id', '{"values": ["com.nettalco.publicidad"]}'::jsonb, true);

-- 3. Agregar targeting por roles
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (CAMPAIGN_ID, 'user_role', '{"roles": ["COMERCIAL_JEFE"]}'::jsonb, true);

-- 4. Agregar targeting por departamento
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (CAMPAIGN_ID, 'department', '{"departments": ["COMERCIAL", "VENTAS"]}'::jsonb, true);
```

---

## 📊 Testing

### Verificar que la tabla existe:

```sql
SELECT COUNT(*) FROM app_clients;
```

### Verificar targeting rules:

```sql
SELECT c.name, tr.rule_type, tr.rule_value
FROM targeting_rules tr
JOIN campaigns c ON c.id = tr.campaign_id
WHERE tr.rule_type IN ('app_id', 'slot', 'user_role', 'department');
```

### Test de autenticación:

```bash
# Sin API Key (debe funcionar)
curl http://localhost:8000/api/v1/health

# Con API Key inválida (debe fallar 401)
curl -H "X-API-Key: invalid_key" \
  http://localhost:8000/api/v1/ad/request

# Con API Key válida (debe funcionar)
curl -H "X-API-Key: TU_API_KEY" \
  http://localhost:8000/api/v1/ad/request
```

---

## 🔒 Seguridad

### Para Habilitar Autenticación Obligatoria

Modificar `liteads/ad_server/middleware/auth.py`:

```python
async def verify_api_key(
    request: Request,
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
) -> Optional[AppClient]:
    # COMENTAR ESTAS LÍNEAS para requerir API key:
    # if not x_api_key:
    #     logger.debug("No API key provided, allowing access")
    #     return None
    
    # DESCOMENTAR para requerir API key:
    if not x_api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="API key required",
        )
```

### IP Whitelisting (Preparado, no implementado)

```sql
UPDATE app_clients 
SET allowed_ips = '["192.168.1.0/24", "10.0.0.0/8"]'::jsonb
WHERE app_id = 'com.nettalco.publicidad';
```

Implementar en `auth.py`:
```python
# TODO: Implement CIDR validation
import ipaddress
if app_client.allowed_ips and client_ip:
    # Check if client_ip is in allowed ranges
    pass
```

---

## 📝 Próximos Pasos

### Recomendaciones para Producción

1. **Habilitar autenticación obligatoria** (ver sección Seguridad)
2. **Configurar CORS específico** (actualizar `main.py` con dominios permitidos)
3. **Implementar IP whitelisting** (agregar validación CIDR en `auth.py`)
4. **Rate limiting** (implementar usando Redis)
5. **Monitoreo** (configurar Grafana/Prometheus dashboards)

### Funcionalidades Adicionales Sugeridas

- [ ] Rate limiting por API key
- [ ] Logs de auditoría de accesos
- [ ] Dashboard de gestión de app_clients
- [ ] Rotación automática de API keys
- [ ] Webhooks para eventos importantes

---

## 📚 Documentación Relacionada

- [INTEGRACION_NETTALCO.md](./INTEGRACION_NETTALCO.md) - Guía de integración completa
- [INTEGRACION_USUARIOS_INTERNOS.md](./INTEGRACION_USUARIOS_INTERNOS.md) - Específico para usuarios internos
- [SQL_SETUP_NETTALCO.sql](./SQL_SETUP_NETTALCO.sql) - Script de setup de base de datos

---

## ⚠️ Notas Importantes

1. **Backwards Compatibility**: Todas las funcionalidades son retrocompatibles. El sistema funciona sin API key por defecto.

2. **Performance**: Los nuevos índices JSONB pueden tardar en crearse en tablas grandes. Ejecutar en horarios de bajo tráfico.

3. **Migraciones**: Si tienes datos existentes, el script SQL usará `CREATE TABLE IF NOT EXISTS` y no borrará datos.

4. **Testing**: Probar exhaustivamente en desarrollo antes de desplegar a producción.

---

## 🐛 Troubleshooting

### Error: "relation app_clients does not exist"

```bash
# Ejecutar migración
psql -h localhost -U postgres -d liteads < scripts/init_db.sql
```

### Error: "Invalid API key"

```sql
-- Verificar que el cliente existe y está activo
SELECT * FROM app_clients WHERE status = 1;
```

### Targeting no funciona

```sql
-- Verificar que las reglas están bien formateadas
SELECT rule_type, rule_value 
FROM targeting_rules 
WHERE campaign_id = YOUR_CAMPAIGN_ID;

-- Formato correcto:
-- app_id: {"values": ["com.nettalco.publicidad"]}
-- user_role: {"roles": ["COMERCIAL_JEFE"]}
-- department: {"departments": ["SISTEMAS"]}
```

---

**¿Preguntas? Revisar la documentación completa o abrir un issue.**
