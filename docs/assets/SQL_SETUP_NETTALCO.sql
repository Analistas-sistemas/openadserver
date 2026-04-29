-- ============================================================
-- Configuración SQL para Sistema Nettalco (USUARIOS INTERNOS)
-- ============================================================
-- Este script configura el sistema de anuncios para mostrar
-- publicidad a USUARIOS INTERNOS de la empresa Nettalco
-- (empleados, NO clientes externos)
-- ============================================================

-- 1. Crear tabla de clientes/sistemas permitidos
-- ============================================================
CREATE TABLE IF NOT EXISTS app_clients (
    id SERIAL PRIMARY KEY,
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

CREATE INDEX IF NOT EXISTS idx_app_clients_app_id ON app_clients(app_id);
CREATE INDEX IF NOT EXISTS idx_app_clients_api_key ON app_clients(app_id);
CREATE INDEX IF NOT EXISTS idx_app_clients_status ON app_clients(status);

-- 2. Insertar cliente Nettalco
-- ============================================================
INSERT INTO app_clients (app_id, api_key, name, company, allowed_slots, allowed_ips)
VALUES 
  (
    'com.nettalco.publicidad',
    'nettalco_api_key_' || md5(random()::text),  -- Generar API key única
    'Sistema Publicidad Nettalco',
    'Nettalco',
    '["publicidad_nettalco_banner_principal", "publicidad_nettalco_sidebar_top", "publicidad_nettalco_sidebar_bottom", "publicidad_nettalco_inline_feed"]'::jsonb,
    '["192.168.1.0/24", "10.0.0.0/8"]'::jsonb  -- Ajustar según tu red
  )
ON CONFLICT (app_id) DO UPDATE
  SET allowed_slots = EXCLUDED.allowed_slots;

-- Mostrar la API key generada
SELECT 
  app_id, 
  api_key, 
  name,
  allowed_slots
FROM app_clients 
WHERE app_id = 'com.nettalco.publicidad';

-- 3. Crear anunciante de prueba para Nettalco
-- ============================================================
INSERT INTO advertisers (name, company, contact_email, balance, status)
VALUES 
  ('Anunciante Test Nettalco', 'Test Company', 'test@nettalco.com', 50000.00, 1)
ON CONFLICT DO NOTHING
RETURNING id;

-- Guardar el ID del anunciante (ajustar según el resultado anterior)
-- Ejemplo: supongamos que devuelve id = 100

-- 4. Crear campaña de prueba
-- ============================================================
DO $$
DECLARE
    v_advertiser_id BIGINT;
    v_campaign_id BIGINT;
BEGIN
    -- Obtener o crear anunciante
    SELECT id INTO v_advertiser_id 
    FROM advertisers 
    WHERE company = 'Test Company' 
    LIMIT 1;
    
    IF v_advertiser_id IS NULL THEN
        INSERT INTO advertisers (name, company, contact_email, balance, status)
        VALUES ('Anunciante Test Nettalco', 'Test Company', 'test@nettalco.com', 50000.00, 1)
        RETURNING id INTO v_advertiser_id;
    END IF;
    
    -- Crear campaña
    INSERT INTO campaigns (
        advertiser_id, 
        name, 
        description,
        budget_daily, 
        budget_total,
        bid_type, 
        bid_amount, 
        freq_cap_daily,
        freq_cap_hourly,
        status
    )
    VALUES (
        v_advertiser_id,
        'Campaña Test Nettalco - Banner Principal',
        'Campaña de prueba exclusiva para sistema Nettalco',
        1000.00,
        30000.00,
        2, -- CPC
        2.50,
        10,
        3,
        1 -- ACTIVE
    )
    RETURNING id INTO v_campaign_id;
    
    -- Crear creativos
    INSERT INTO creatives (
        campaign_id, 
        title, 
        description, 
        image_url, 
        landing_url,
        creative_type, 
        width, 
        height, 
        status
    )
    VALUES 
        (
            v_campaign_id,
            'Oferta Especial Nettalco',
            '¡Descuento del 30% en todos nuestros servicios!',
            'https://via.placeholder.com/300x250?text=Nettalco+Offer',
            'https://www.nettalco.com/ofertas',
            1, -- BANNER
            300,
            250,
            1 -- ACTIVE
        ),
        (
            v_campaign_id,
            'Banner Lateral Nettalco',
            'Conoce nuestros nuevos planes empresariales',
            'https://via.placeholder.com/160x600?text=Nettalco+Sidebar',
            'https://www.nettalco.com/planes',
            1, -- BANNER
            160,
            600,
            1 -- ACTIVE
        );
    
    -- Crear targeting rules
    -- Rule 1: Solo para app_id de Nettalco (identificar sistema)
    INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
    VALUES (v_campaign_id, 'app_id', '{"values": ["com.nettalco.publicidad"]}'::jsonb, true);
    
    -- Rule 2: Solo para ciertos slots (ubicación en la interfaz)
    INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
    VALUES (v_campaign_id, 'slot', '{"values": ["dashboard_banner_principal", "dashboard_sidebar_top"]}'::jsonb, true);
    
    -- Rule 3: Solo para Perú (país de la empresa)
    INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
    VALUES (v_campaign_id, 'geo', '{"countries": ["PE"]}'::jsonb, true);
    
    -- ⭐ USUARIOS INTERNOS - Ejemplos de targeting por características de empleados:
    
    -- Rule 4: Solo para usuarios con ciertos roles
    -- INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
    -- VALUES (v_campaign_id, 'user_role', '{"roles": ["COMERCIAL_JEFE", "COTIZACIONES_SUPERUSUARIO"]}'::jsonb, true);
    
    -- Rule 5: Solo para departamentos específicos
    -- INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
    -- VALUES (v_campaign_id, 'department', '{"departments": ["SISTEMAS", "COMERCIAL"]}'::jsonb, true);
    
    -- Rule 6: Solo para usuarios con nivel de permisos alto
    -- INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
    -- VALUES (v_campaign_id, 'permission_level', '{"min_level": 100}'::jsonb, true);
    
    -- Rule 7: Solo para administradores
    -- INSERT INTO targeting_rules (campaign_id, rule_type, rule_value, is_include)
    -- VALUES (v_campaign_id, 'is_admin', '{"value": true}'::jsonb, true);
    
    RAISE NOTICE 'Campaña creada con ID: %', v_campaign_id;
END $$;

-- 5. Verificar la configuración
-- ============================================================
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

-- Ver targeting rules de la campaña
SELECT 
    c.name as campaign_name,
    tr.rule_type,
    tr.rule_value,
    tr.is_include
FROM targeting_rules tr
JOIN campaigns c ON c.id = tr.campaign_id
WHERE c.name LIKE '%Nettalco%'
ORDER BY tr.id;

-- Ver creativos de la campaña
SELECT 
    c.name as campaign_name,
    cr.title,
    cr.description,
    cr.width || 'x' || cr.height as dimensions,
    cr.landing_url,
    cr.status
FROM creatives cr
JOIN campaigns c ON c.id = cr.campaign_id
WHERE c.name LIKE '%Nettalco%';

-- 6. Crear índices adicionales para performance
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_targeting_rules_app_id 
ON targeting_rules ((rule_value->>'values')) 
WHERE rule_type = 'app_id';

CREATE INDEX IF NOT EXISTS idx_targeting_rules_slot 
ON targeting_rules ((rule_value->>'values')) 
WHERE rule_type = 'slot';

-- 7. Función helper para validar API keys
-- ============================================================
CREATE OR REPLACE FUNCTION validate_api_key(p_api_key VARCHAR, p_app_id VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM app_clients
    WHERE api_key = p_api_key 
      AND app_id = p_app_id
      AND status = 1;
    
    RETURN v_count > 0;
END;
$$ LANGUAGE plpgsql;

-- Ejemplo de uso:
-- SELECT validate_api_key('la_api_key_aqui', 'com.nettalco.publicidad');

-- 8. Vista para monitoreo de anuncios por sistema
-- ============================================================
CREATE OR REPLACE VIEW v_ads_by_system AS
SELECT 
    ac.app_id,
    ac.name as system_name,
    c.id as campaign_id,
    c.name as campaign_name,
    COUNT(DISTINCT ae.id) as total_events,
    SUM(CASE WHEN ae.event_type = 1 THEN 1 ELSE 0 END) as impressions,
    SUM(CASE WHEN ae.event_type = 2 THEN 1 ELSE 0 END) as clicks,
    SUM(CASE WHEN ae.event_type = 3 THEN 1 ELSE 0 END) as conversions,
    SUM(ae.cost) as total_cost,
    CASE 
        WHEN SUM(CASE WHEN ae.event_type = 1 THEN 1 ELSE 0 END) > 0 
        THEN ROUND(
            SUM(CASE WHEN ae.event_type = 2 THEN 1 ELSE 0 END)::NUMERIC / 
            SUM(CASE WHEN ae.event_type = 1 THEN 1 ELSE 0 END) * 100, 
            2
        )
        ELSE 0 
    END as ctr_percentage
FROM app_clients ac
CROSS JOIN campaigns c
LEFT JOIN ad_events ae ON ae.campaign_id = c.id
WHERE c.status = 1
GROUP BY ac.app_id, ac.name, c.id, c.name;

-- Ver estadísticas
SELECT * FROM v_ads_by_system WHERE app_id = 'com.nettalco.publicidad';

-- ============================================================
-- NOTAS IMPORTANTES:
-- ============================================================
-- 1. Guardar la API key generada en paso 2
-- 2. Ajustar allowed_ips según tu infraestructura
-- 3. Personalizar las campañas y creativos según necesidad
-- 4. Los IDs pueden variar, ajustar según tu base de datos
-- ============================================================
