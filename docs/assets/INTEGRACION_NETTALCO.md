# Integración OpenAdServer con Sistema Nettalco

## 🔧 Configuración en Base de Datos

### 1. Crear Targeting Rules para filtrar por app_id/sistema_id

El sistema actual soporta estos `rule_type`:
- `age`, `gender`, `geo`, `os`, `device`, `interest`, `app_category`

**NECESITAS AGREGAR** soporte para filtrar por `app_id` o `slot_id`:

```sql
-- Opción 1: Usar app_category como "sistema"
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES 
  (1, 'app_category', '{"values": ["nettalco_publicidad"]}', true);

-- Opción 2: Extender con nuevo rule_type "app_id"
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES 
  (1, 'app_id', '{"values": ["com.nettalco.publicidad"]}', true);

-- Opción 3: Usar slot_id en la campaña (más simple)
-- Solo mostrar anuncios cuando se soliciten desde ciertos slots
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES 
  (1, 'slot', '{"values": ["publicidad_nettalco_banner_principal", "publicidad_nettalco_sidebar"]}', true);
```

### 2. Extender el código de targeting (targeting.py)

Agregar al método `_match_rule()` en:
`liteads/rec_engine/retrieval/targeting.py`

```python
elif rule_type == "app_id":
    app_ids = rule_value.get("values", [])
    if app_ids and user_context.app_id:
        if user_context.app_id not in app_ids:
            return False
    return True

elif rule_type == "slot":
    slots = rule_value.get("values", [])
    if slots and hasattr(user_context, 'slot_id'):
        if user_context.slot_id not in slots:
            return False
    return True
```

### 3. Extender UserContext para incluir slot_id

En `liteads/schemas/internal.py`, agregar:

```python
@dataclass
class UserContext:
    # ... campos existentes ...
    slot_id: str = ""  # ⭐ NUEVO: identificador del slot
```

Y en `liteads/ad_server/services/ad_service.py`:

```python
def _build_user_context(self, request: AdRequest) -> UserContext:
    ctx = UserContext(
        user_id=request.user_id,
        user_hash=hash_user_id(request.user_id) if request.user_id else 0,
        slot_id=request.slot_id,  # ⭐ NUEVO
    )
    # ... resto del código ...
```

## 🔐 Autenticación y Autorización

### Estado Actual
El sistema **NO tiene autenticación** por defecto. Cualquiera puede solicitar anuncios.

### Opciones de Seguridad

#### Opción 1: API Key simple (Recomendado para inicio)

En `liteads/ad_server/main.py`:

```python
from fastapi import Header, HTTPException

async def verify_api_key(x_api_key: str = Header(...)):
    valid_keys = {
        "nettalco_key_123": "Sistema Nettalco",
        "mobile_app_key": "App Móvil",
    }
    if x_api_key not in valid_keys:
        raise HTTPException(status_code=401, detail="API Key inválida")
    return valid_keys[x_api_key]

# Agregar a los endpoints
@router.post("/request", dependencies=[Depends(verify_api_key)])
async def request_ads(...):
    # ...
```

Request desde tu sistema:
```typescript
headers: {
  'Content-Type': 'application/json',
  'X-API-Key': 'nettalco_key_123'
}
```

#### Opción 2: OAuth2/JWT (Producción)

```python
from fastapi import Depends
from fastapi.security import HTTPBearer

security = HTTPBearer()

async def verify_token(credentials = Depends(security)):
    token = credentials.credentials
    # Validar JWT con tu sistema existente
    payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
    return payload
```

#### Opción 3: IP Whitelist (Más restrictivo)

```python
from fastapi import Request

ALLOWED_IPS = ["192.168.1.100", "10.0.0.5"]

async def verify_ip(request: Request):
    client_ip = request.client.host
    if client_ip not in ALLOWED_IPS:
        raise HTTPException(status_code=403, detail="IP no autorizada")
```

## 📊 Configuración por Sistema/Cliente

### Tabla de configuración recomendada

```sql
-- Agregar tabla para gestionar sistemas permitidos
CREATE TABLE app_clients (
    id SERIAL PRIMARY KEY,
    app_id VARCHAR(255) UNIQUE NOT NULL,
    api_key VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    allowed_slots JSONB,  -- ["banner_principal", "sidebar"]
    status SMALLINT DEFAULT 1,
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO app_clients (app_id, api_key, name, allowed_slots)
VALUES 
  ('com.nettalco.publicidad', 'nettalco_key_123', 'Sistema Publicidad Nettalco', 
   '["publicidad_nettalco_banner_principal", "publicidad_nettalco_sidebar"]'),
  ('com.nettalco.mobile', 'mobile_key_456', 'App Móvil Nettalco',
   '["mobile_banner_home", "mobile_native_feed"]');
```

## 🎯 Ejemplo Completo de Integración

### Backend (publicidad-backend-ws)

```javascript
// src/modules/anuncios/services/adserver.service.js
const axios = require('axios');

class AdServerService {
  constructor() {
    this.baseUrl = process.env.AD_SERVER_URL || 'http://localhost:8000/api/v1';
    this.apiKey = process.env.AD_SERVER_API_KEY || 'nettalco_key_123';
  }

  async solicitarAnuncio(params) {
    const { userId, slotId, userContext } = params;
    
    const request = {
      slot_id: slotId || 'publicidad_nettalco_banner_principal',
      user_id: userId,
      num_ads: 1,
      device: {
        os: userContext.device?.os || 'web',
        language: userContext.language || 'es'
      },
      geo: {
        country: userContext.country || 'EC',
        city: userContext.city
      },
      context: {
        app_id: 'com.nettalco.publicidad',
        app_name: 'Publicidad Nettalco',
        app_version: '1.0.0'
      },
      user_features: {
        age: userContext.age,
        gender: userContext.gender,
        interests: userContext.interests || [],
        custom: {
          sistema_id: params.sistemaId || 1,
          perfil: userContext.perfil
        }
      }
    };

    try {
      const response = await axios.post(`${this.baseUrl}/ad/request`, request, {
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': this.apiKey
        },
        timeout: 3000 // 3 segundos timeout
      });

      return response.data.ads[0] || null;
    } catch (error) {
      console.error('Error solicitando anuncio:', error.message);
      return null; // Graceful degradation
    }
  }

  async trackEvent(eventType, adId, requestId) {
    const url = `${this.baseUrl}/event/track?type=${eventType}&ad=${adId}&req=${requestId}`;
    
    try {
      await axios.get(url, { timeout: 1000 });
    } catch (error) {
      console.error('Error tracking event:', error.message);
    }
  }
}

module.exports = new AdServerService();
```

### Frontend (publicidad-frontend-angular)

```typescript
// src/app/services/ad-server.service.ts
import { Injectable } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable, of } from 'rxjs';
import { catchError, timeout } from 'rxjs/operators';

export interface AnuncioResponse {
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

@Injectable({ providedIn: 'root' })
export class AdServerService {
  private baseUrl = 'http://localhost:8000/api/v1';
  private apiKey = 'nettalco_key_123';

  constructor(private http: HttpClient) {}

  solicitarAnuncio(slotId: string, userId?: string): Observable<AnuncioResponse | null> {
    const headers = new HttpHeaders({
      'Content-Type': 'application/json',
      'X-API-Key': this.apiKey
    });

    const request = {
      slot_id: slotId,
      user_id: userId || 'anonymous',
      num_ads: 1,
      device: {
        os: this.detectOS(),
        language: navigator.language
      },
      geo: {
        country: 'EC'
      },
      context: {
        app_id: 'com.nettalco.publicidad',
        app_name: 'Publicidad Nettalco Web',
        app_version: '1.0.0'
      }
    };

    return this.http.post<any>(`${this.baseUrl}/ad/request`, request, { headers })
      .pipe(
        timeout(3000),
        catchError(error => {
          console.error('Error solicitando anuncio:', error);
          return of(null);
        })
      )
      .pipe(
        map(response => response?.ads?.[0] || null)
      );
  }

  trackImpression(url: string): void {
    // Usar imagen de 1x1 pixel para tracking sin bloquear UI
    const img = new Image();
    img.src = url;
  }

  trackClick(url: string): void {
    navigator.sendBeacon(url); // No bloquea navegación
  }

  private detectOS(): string {
    const ua = navigator.userAgent.toLowerCase();
    if (ua.includes('android')) return 'android';
    if (ua.includes('iphone') || ua.includes('ipad')) return 'ios';
    if (ua.includes('windows')) return 'windows';
    if (ua.includes('mac')) return 'macos';
    return 'web';
  }
}
```

### Componente de Anuncio

```typescript
// src/app/components/ad-banner/ad-banner.component.ts
import { Component, Input, OnInit } from '@angular/core';
import { AdServerService, AnuncioResponse } from '@services/ad-server.service';

@Component({
  selector: 'app-ad-banner',
  template: `
    <div class="ad-container" *ngIf="anuncio">
      <div class="ad-label">Publicidad</div>
      <a 
        [href]="anuncio.creative.landing_url" 
        target="_blank"
        (click)="onClickAnuncio()"
        class="ad-link">
        <img 
          [src]="anuncio.creative.image_url" 
          [alt]="anuncio.creative.title"
          (load)="onImpressionAnuncio()"
          class="ad-image">
        <div class="ad-content">
          <h4>{{ anuncio.creative.title }}</h4>
          <p>{{ anuncio.creative.description }}</p>
        </div>
      </a>
    </div>
  `,
  styles: [`
    .ad-container {
      border: 1px solid #e0e0e0;
      border-radius: 8px;
      padding: 16px;
      margin: 16px 0;
      background: #f9f9f9;
    }
    .ad-label {
      font-size: 10px;
      color: #999;
      text-transform: uppercase;
      margin-bottom: 8px;
    }
    .ad-link {
      text-decoration: none;
      color: inherit;
    }
    .ad-image {
      width: 100%;
      border-radius: 4px;
    }
  `]
})
export class AdBannerComponent implements OnInit {
  @Input() slotId = 'publicidad_nettalco_banner_principal';
  @Input() userId?: string;
  
  anuncio: AnuncioResponse | null = null;

  constructor(private adService: AdServerService) {}

  ngOnInit(): void {
    this.cargarAnuncio();
  }

  cargarAnuncio(): void {
    this.adService.solicitarAnuncio(this.slotId, this.userId)
      .subscribe(anuncio => {
        this.anuncio = anuncio;
      });
  }

  onImpressionAnuncio(): void {
    if (this.anuncio?.tracking?.impression_url) {
      this.adService.trackImpression(this.anuncio.tracking.impression_url);
    }
  }

  onClickAnuncio(): void {
    if (this.anuncio?.tracking?.click_url) {
      this.adService.trackClick(this.anuncio.tracking.click_url);
    }
  }
}
```

## 🚀 Slots Recomendados para tu Sistema

```typescript
export const AD_SLOTS = {
  BANNER_PRINCIPAL: 'publicidad_nettalco_banner_principal',
  SIDEBAR_TOP: 'publicidad_nettalco_sidebar_top',
  SIDEBAR_BOTTOM: 'publicidad_nettalco_sidebar_bottom',
  INLINE_FEED: 'publicidad_nettalco_inline_feed',
  MOBILE_BANNER: 'publicidad_nettalco_mobile_banner',
  NATIVE_CARD: 'publicidad_nettalco_native_card'
} as const;
```

## 📝 Configuración de Campañas

Para que una campaña se muestre SOLO en tu sistema:

```sql
-- Crear campaña
INSERT INTO campaigns (advertiser_id, name, budget_daily, bid_amount, status)
VALUES (1, 'Campaña Exclusiva Nettalco', 1000.00, 5.00, 1)
RETURNING id; -- Supongamos que devuelve id=10

-- Agregar targeting rule para app_id
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (10, 'app_id', '{"values": ["com.nettalco.publicidad"]}', true);

-- O targeting por slot_id
INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
VALUES (10, 'slot', '{"values": ["publicidad_nettalco_banner_principal"]}', true);
```

## ✅ Checklist de Integración

- [ ] Extender `targeting.py` con soporte para `app_id` o `slot`
- [ ] Extender `UserContext` con `slot_id`
- [ ] Implementar autenticación (API Key mínimo)
- [ ] Crear tabla `app_clients` para gestionar sistemas
- [ ] Configurar campañas con targeting rules para tu sistema
- [ ] Implementar servicio en backend (publicidad-backend-ws)
- [ ] Implementar servicio en frontend (publicidad-frontend-angular)
- [ ] Crear componente de visualización de anuncios
- [ ] Implementar tracking de eventos (impression, click, conversion)
- [ ] Configurar slots específicos para diferentes ubicaciones
- [ ] Probar con datos de prueba
- [ ] Configurar CORS en openadserver para permitir requests desde frontend
- [ ] Deploy y monitoreo

## 🔒 Seguridad en Producción

```python
# liteads/ad_server/main.py
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://publicidad.nettalco.com",
        "https://app.nettalco.com"
    ],
    allow_credentials=True,
    allow_methods=["POST", "GET"],
    allow_headers=["Content-Type", "X-API-Key"],
)
```
