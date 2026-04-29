# Integración OpenAdServer para Usuarios Internos Nettalco

## 🎯 Contexto

El sistema de anuncios está diseñado para mostrar publicidad a **usuarios internos de la empresa Nettalco** (empleados), NO a clientes externos.

## 👥 Sistema de Usuarios

### Estructura de Usuario Interno

```javascript
{
  "id": "000016570",  // tcodipers
  "codigo_personal": "E004629",
  "nombres": "DIEGO DENILSON",
  "apellido_paterno": "SULLCARAY",
  "apellido_materno": "RAMOS",
  "nombre_completo": "DIEGO DENILSON SULLCARAY RAMOS",
  "email": "dsullcaray@nettalco.com.pe",
  "cargo": "ANALISTA DE SISTEMAS JUNIOR",
  "unidad_funcional": "SISTEMAS",
  "activo": true,
  "roles": [
    {
      "rolId": 10,
      "codigo": "COTIZACIONES_SUPERUSUARIO",
      "descripcion": "SuperUsuario Cotizaciones",
      "nivel": 150
    }
  ]
}
```

## 📡 Endpoint de Anuncios

**POST** `http://localhost:8000/api/v1/ad/request`

### Request desde Backend (publicidad-backend-ws)

```javascript
// src/modules/anuncios/services/adserver.service.js
const axios = require('axios');
const logger = require('../../../infrastructure/logging');

class AdServerService {
  constructor() {
    this.baseUrl = process.env.AD_SERVER_URL || 'http://localhost:8000/api/v1';
    this.timeout = 3000; // 3 segundos
  }

  /**
   * Solicitar anuncio para usuario interno
   * @param {Object} params
   * @param {Object} params.user - Usuario de req.user (tcodipers, cargo, unidad_funcional, roles)
   * @param {string} params.slotId - Slot del anuncio ('dashboard_banner', 'sidebar_top', etc)
   * @param {Object} params.context - Contexto adicional (ip, userAgent, etc)
   */
  async solicitarAnuncioParaUsuario({ user, slotId, context = {} }) {
    if (!user || !user.tcodipers) {
      logger.warn('Usuario no proporcionado para solicitud de anuncio', {
        module: 'AdServerService',
        method: 'solicitarAnuncioParaUsuario'
      });
      return null;
    }

    const request = {
      slot_id: slotId || 'publicidad_nettalco_banner_principal',
      user_id: user.tcodipers, // ID interno del empleado
      num_ads: 1,
      
      device: {
        os: context.platform || 'web',
        language: context.language || 'es'
      },
      
      geo: {
        country: 'PE', // Perú (Nettalco)
        ip: context.ip
      },
      
      context: {
        app_id: 'com.nettalco.publicidad',
        app_name: 'Sistema Publicidad Nettalco',
        app_version: '1.0.0'
      },
      
      user_features: {
        // Mapear características del usuario interno
        custom: {
          tcodipers: user.tcodipers,
          codigo_personal: user.codigo_personal,
          cargo: user.cargo,
          unidad_funcional: user.unidad_funcional,
          roles: user.roles?.map(r => r.codigo) || [],
          nivel_mas_alto: Math.max(...(user.roles?.map(r => r.nivel) || [0])),
          es_admin: user.roles?.some(r => r.codigo.includes('SUPER')) || false
        }
      }
    };

    try {
      const response = await axios.post(
        `${this.baseUrl}/ad/request`, 
        request,
        {
          timeout: this.timeout,
          headers: {
            'Content-Type': 'application/json'
          }
        }
      );

      const anuncio = response.data?.ads?.[0];
      
      if (anuncio) {
        logger.debug('Anuncio obtenido exitosamente', {
          module: 'AdServerService',
          tcodipers: user.tcodipers,
          slotId,
          adId: anuncio.ad_id
        });
      }

      return anuncio;
    } catch (error) {
      // Graceful degradation: si falla, no romper la aplicación
      logger.error('Error solicitando anuncio', {
        module: 'AdServerService',
        error: error.message,
        tcodipers: user.tcodipers,
        slotId
      });
      return null;
    }
  }

  /**
   * Registrar evento de anuncio (impression, click, conversion)
   */
  async trackEvent(eventType, adId, requestId, userId) {
    const url = `${this.baseUrl}/event/track?type=${eventType}&ad=${adId}&req=${requestId}`;
    
    try {
      await axios.get(url, { 
        timeout: 1000,
        params: { user_id: userId }
      });
      
      logger.debug(`Evento ${eventType} registrado`, {
        module: 'AdServerService',
        eventType,
        adId,
        userId
      });
    } catch (error) {
      logger.warn('Error registrando evento de anuncio', {
        module: 'AdServerService',
        error: error.message,
        eventType,
        adId
      });
    }
  }
}

module.exports = new AdServerService();
```

### Ejemplo de uso en Controller

```javascript
// src/modules/dashboard/controllers/dashboard.controller.js
const adServerService = require('../../anuncios/services/adserver.service');

class DashboardController {
  /**
   * GET /api/v1/dashboard/inicio
   * Obtener datos del dashboard + anuncio contextual
   */
  async getInicio(req, res, next) {
    try {
      const user = req.user; // Viene de auth.middleware

      // Datos del dashboard
      const dashboardData = await this.getDashboardData(user);

      // Solicitar anuncio contextual
      const anuncio = await adServerService.solicitarAnuncioParaUsuario({
        user,
        slotId: 'dashboard_banner_principal',
        context: {
          ip: req.ip,
          language: req.headers['accept-language']?.split(',')[0],
          platform: 'web'
        }
      });

      res.json({
        success: true,
        data: {
          ...dashboardData,
          anuncio // Puede ser null si no hay anuncios
        }
      });
    } catch (error) {
      next(error);
    }
  }
}
```

## 🎨 Frontend Angular - Componente de Anuncio

```typescript
// src/app/shared/components/ad-banner/ad-banner.component.ts
import { Component, Input, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { environment } from '@environment/environment';

export interface Anuncio {
  ad_id: string;
  creative: {
    title: string;
    description: string;
    image_url: string;
    landing_url: string;
    width: number;
    height: number;
  };
  tracking: {
    impression_url: string;
    click_url: string;
    conversion_url?: string;
  };
}

@Component({
  selector: 'app-ad-banner',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="ad-banner-wrapper" *ngIf="anuncio">
      <div class="ad-label">
        <i class="pi pi-info-circle"></i>
        Publicidad
      </div>
      <a 
        [href]="anuncio.creative.landing_url" 
        target="_blank"
        rel="noopener noreferrer"
        (click)="onClickAnuncio($event)"
        class="ad-link">
        <img 
          [src]="anuncio.creative.image_url" 
          [alt]="anuncio.creative.title"
          [width]="anuncio.creative.width"
          [height]="anuncio.creative.height"
          (load)="onImpressionAnuncio()"
          (error)="onErrorImagen()"
          class="ad-image">
        <div class="ad-content" *ngIf="showContent">
          <h4 class="ad-title">{{ anuncio.creative.title }}</h4>
          <p class="ad-description">{{ anuncio.creative.description }}</p>
        </div>
      </a>
    </div>
  `,
  styles: [`
    .ad-banner-wrapper {
      border: 1px solid var(--surface-border);
      border-radius: 8px;
      padding: 12px;
      margin: 16px 0;
      background: var(--surface-ground);
      box-shadow: 0 2px 4px rgba(0,0,0,0.05);
    }
    
    .ad-label {
      display: flex;
      align-items: center;
      gap: 4px;
      font-size: 10px;
      color: var(--text-color-secondary);
      text-transform: uppercase;
      margin-bottom: 8px;
      font-weight: 500;
    }
    
    .ad-link {
      text-decoration: none;
      color: inherit;
      display: block;
    }
    
    .ad-image {
      width: 100%;
      height: auto;
      border-radius: 4px;
      display: block;
    }
    
    .ad-content {
      margin-top: 12px;
    }
    
    .ad-title {
      margin: 0 0 8px 0;
      font-size: 16px;
      font-weight: 600;
      color: var(--text-color);
    }
    
    .ad-description {
      margin: 0;
      font-size: 14px;
      color: var(--text-color-secondary);
      line-height: 1.5;
    }

    .ad-banner-wrapper:hover {
      border-color: var(--primary-color);
      box-shadow: 0 4px 8px rgba(0,0,0,0.1);
      transition: all 0.3s ease;
    }
  `]
})
export class AdBannerComponent implements OnInit, OnDestroy {
  @Input() anuncio: Anuncio | null = null;
  @Input() showContent = true; // Mostrar título/descripción

  private impressionTracked = false;

  constructor(private http: HttpClient) {}

  ngOnInit(): void {
    // El anuncio viene desde el padre (ya solicitado en backend)
  }

  onImpressionAnuncio(): void {
    if (this.impressionTracked || !this.anuncio?.tracking?.impression_url) {
      return;
    }

    this.impressionTracked = true;

    // Tracking mediante pixel de 1x1
    const img = new Image();
    img.src = this.anuncio.tracking.impression_url;
    
    console.debug('Impresión registrada:', this.anuncio.ad_id);
  }

  onClickAnuncio(event: MouseEvent): void {
    if (!this.anuncio?.tracking?.click_url) {
      return;
    }

    // No bloquear navegación, usar sendBeacon
    if (navigator.sendBeacon) {
      navigator.sendBeacon(this.anuncio.tracking.click_url);
    } else {
      // Fallback para navegadores antiguos
      const img = new Image();
      img.src = this.anuncio.tracking.click_url;
    }

    console.debug('Click registrado:', this.anuncio.ad_id);
  }

  onErrorImagen(): void {
    console.warn('Error cargando imagen de anuncio:', this.anuncio?.ad_id);
    // Opcionalmente: ocultar el anuncio
    this.anuncio = null;
  }

  ngOnDestroy(): void {
    // Cleanup si es necesario
  }
}
```

### Uso en componentes:

```typescript
// src/app/dashboard/inicio/inicio.component.ts
import { Component, OnInit } from '@angular/core';
import { DashboardService } from '@services/dashboard.service';
import { AdBannerComponent, Anuncio } from '@shared/components/ad-banner/ad-banner.component';

@Component({
  selector: 'app-dashboard-inicio',
  standalone: true,
  imports: [CommonModule, AdBannerComponent],
  template: `
    <div class="dashboard-container">
      <h1>Bienvenido {{ nombreUsuario }}</h1>
      
      <!-- Anuncio desde backend -->
      <app-ad-banner 
        [anuncio]="dashboardData?.anuncio"
        [showContent]="true">
      </app-ad-banner>
      
      <!-- Resto del contenido del dashboard -->
      <div class="dashboard-widgets">
        <!-- ... -->
      </div>
    </div>
  `
})
export class DashboardInicioComponent implements OnInit {
  dashboardData: any;
  nombreUsuario = '';

  constructor(private dashboardService: DashboardService) {}

  ngOnInit(): void {
    this.cargarDatos();
  }

  cargarDatos(): void {
    this.dashboardService.getInicio().subscribe(response => {
      if (response.success) {
        this.dashboardData = response.data;
        // El anuncio viene incluido en response.data.anuncio
      }
    });
  }
}
```

## 🎯 Targeting por Características de Usuario Interno

### Ejemplo 1: Anuncios solo para Jefes

```sql
-- Crear campaña para jefes
INSERT INTO campaigns (advertiser_id, name, budget_daily, bid_amount, status)
VALUES (1, 'Capacitación Gerencial', 1000.00, 5.00, 1)
RETURNING id; -- id = 20

-- Targeting por rol/cargo en custom features
-- NOTA: Esto requiere extender el targeting.py para soportar "custom_features"
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (20, 'user_role', '{"roles": ["COMERCIAL_JEFE", "COTIZACIONES_SUPERUSUARIO"]}'::jsonb, true);
```

### Ejemplo 2: Anuncios para departamento específico

```sql
-- Solo para unidad funcional SISTEMAS
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (20, 'department', '{"departments": ["SISTEMAS", "TI"]}'::jsonb, true);
```

### Ejemplo 3: Anuncios por nivel de permisos

```sql
-- Solo para usuarios con nivel >= 100
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (20, 'permission_level', '{"min_level": 100}'::jsonb, true);
```

## 🔧 Extender Targeting para Custom Features

Agregar al archivo `liteads/rec_engine/retrieval/targeting.py`:

```python
def _match_rule(
    self,
    rule_type: str,
    rule_value: dict[str, Any],
    user_context: UserContext,
) -> bool:
    """Match a single targeting rule against user context."""
    
    # ... código existente ...
    
    elif rule_type == "user_role":
        # Targeting por roles de usuario
        target_roles = rule_value.get("roles", [])
        user_roles = user_context.custom_features.get("roles", [])
        
        if target_roles and user_roles:
            # Match si el usuario tiene alguno de los roles objetivo
            return any(role in user_roles for role in target_roles)
        return True
    
    elif rule_type == "department":
        # Targeting por unidad funcional/departamento
        target_departments = [d.upper() for d in rule_value.get("departments", [])]
        user_department = user_context.custom_features.get("unidad_funcional", "").upper()
        
        if target_departments and user_department:
            return user_department in target_departments
        return True
    
    elif rule_type == "permission_level":
        # Targeting por nivel de permisos
        min_level = rule_value.get("min_level", 0)
        max_level = rule_value.get("max_level", 9999)
        user_level = user_context.custom_features.get("nivel_mas_alto", 0)
        
        return min_level <= user_level <= max_level
    
    elif rule_type == "is_admin":
        # Targeting solo para administradores
        require_admin = rule_value.get("value", False)
        is_admin = user_context.custom_features.get("es_admin", False)
        
        return is_admin if require_admin else True
    
    # ... resto del código ...
```

## 📊 Slots Recomendados para Sistema Interno

```javascript
// src/config/ad-slots.config.js
module.exports = {
  // Dashboard
  DASHBOARD_BANNER_PRINCIPAL: 'dashboard_banner_principal',
  DASHBOARD_SIDEBAR_TOP: 'dashboard_sidebar_top',
  
  // Anunciantes
  ANUNCIANTES_LISTA_TOP: 'anunciantes_lista_top',
  ANUNCIANTES_DETALLE_SIDEBAR: 'anunciantes_detalle_sidebar',
  
  // Campañas
  CAMPANAS_LISTA_BANNER: 'campanas_lista_banner',
  CAMPANAS_NUEVA_LATERAL: 'campanas_nueva_lateral',
  
  // Reportes
  REPORTES_HEADER: 'reportes_header',
  REPORTES_FOOTER: 'reportes_footer',
  
  // Global
  SIDEBAR_GLOBAL_BOTTOM: 'sidebar_global_bottom',
  NOTIFICACIONES_INLINE: 'notificaciones_inline'
};
```

## ✅ Checklist de Implementación

- [ ] **Backend:**
  - [ ] Crear `src/modules/anuncios/services/adserver.service.js`
  - [ ] Agregar variable `AD_SERVER_URL` en `.env`
  - [ ] Modificar controllers para incluir anuncios en respuestas
  - [ ] Agregar tracking de eventos

- [ ] **Frontend:**
  - [ ] Crear componente `AdBannerComponent`
  - [ ] Importar en módulos necesarios
  - [ ] Agregar slots en templates de componentes
  - [ ] Implementar tracking de impresiones/clicks

- [ ] **OpenAdServer:**
  - [ ] Ejecutar `SQL_SETUP_NETTALCO.sql`
  - [ ] Extender `targeting.py` con reglas custom
  - [ ] Crear campañas de prueba
  - [ ] Configurar CORS para frontend

- [ ] **Testing:**
  - [ ] Probar con diferentes usuarios/roles
  - [ ] Verificar tracking de eventos
  - [ ] Validar graceful degradation si ad server está caído
  - [ ] Medir performance (< 100ms overhead)

## 🔒 Seguridad

### Autenticación
- **No requiere API key** ya que se integra con sistema interno
- Los anuncios se solicitan desde backend autenticado
- El frontend recibe el anuncio ya en la respuesta del API

### Privacidad
- No se envían datos sensibles al ad server
- Solo características agregadas (cargo, departamento, roles)
- IPs internas NO se registran en tracking

### Performance
- Timeout de 3 segundos máximo
- Graceful degradation: si falla, no afecta funcionalidad
- Cache en frontend (opcional)

## 📝 Notas Importantes

1. **No romper funcionalidad existente**: Si el ad server está caído, el sistema funciona normal sin anuncios
2. **Performance**: Las solicitudes deben ser rápidas (< 100ms idealmente)
3. **Privacidad**: No enviar datos personales sensibles (emails, documentos)
4. **UX**: Anuncios deben ser relevantes y no intrusivos
5. **Monitoreo**: Registrar métricas de impresiones/clicks para análisis
