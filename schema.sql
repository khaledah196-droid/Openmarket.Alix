-- ============================================================
-- OpenMarket | هيكل قاعدة البيانات الكامل
-- نظام توصيل طلبات للمنازل - الإسكندرية، مصر
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- الجزء 1: الأساسيات، المستخدمين، السائقين، المناطق
CREATE TABLE IF NOT EXISTS users (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name           VARCHAR(150)    NOT NULL,
    phone               VARCHAR(20)     NOT NULL UNIQUE,
    email               VARCHAR(255)    UNIQUE,
    password_hash       TEXT            NOT NULL,
    avatar_url          TEXT,
    date_of_birth       DATE,
    gender              VARCHAR(10)     CHECK (gender IN ('male', 'female', 'other')),
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    is_verified         BOOLEAN         NOT NULL DEFAULT FALSE,
    preferred_language  VARCHAR(10)     NOT NULL DEFAULT 'ar',
    fcm_token           TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  users IS 'المستخدمون (العملاء)';
COMMENT ON COLUMN users.phone IS 'يُستخدم لتسجيل الدخول والتحقق عبر OTP';

CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users_own_data" ON users;
CREATE POLICY "users_own_data" ON users
    FOR ALL USING (auth.uid() = id);

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- السائقين
CREATE TABLE IF NOT EXISTS drivers (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name           VARCHAR(150)    NOT NULL,
    phone               VARCHAR(20)     NOT NULL UNIQUE,
    email               VARCHAR(255)    UNIQUE,
    password_hash       TEXT            NOT NULL,
    national_id         VARCHAR(20)     NOT NULL UNIQUE,
    avatar_url          TEXT,
    vehicle_type        VARCHAR(50)     NOT NULL CHECK (vehicle_type IN ('motorcycle','bicycle','car','tuktuk')),
    vehicle_plate       VARCHAR(20)     NOT NULL UNIQUE,
    vehicle_model       VARCHAR(100),
    vehicle_color       VARCHAR(50),
    license_url         TEXT,
    status              VARCHAR(20)     NOT NULL DEFAULT 'offline' CHECK (status IN ('online','offline','busy','suspended')),
    current_lat         DECIMAL(10,8),
    current_lng         DECIMAL(11,8),
    last_location_at    TIMESTAMPTZ,
    rating              DECIMAL(3,2)    NOT NULL DEFAULT 5.00 CHECK (rating >= 0 AND rating <= 5),
    total_deliveries    INT             NOT NULL DEFAULT 0,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    fcm_token           TEXT,
    wallet_balance      DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  drivers IS 'السائقون';
COMMENT ON COLUMN drivers.status IS 'online=متاح | offline=غير متاح | busy=مشغول | suspended=موقوف';

CREATE INDEX IF NOT EXISTS idx_drivers_status ON drivers(status);
CREATE INDEX IF NOT EXISTS idx_drivers_location ON drivers(current_lat, current_lng);
CREATE INDEX IF NOT EXISTS idx_drivers_phone ON drivers(phone);

DROP TRIGGER IF EXISTS trg_drivers_updated_at ON drivers;
CREATE TRIGGER trg_drivers_updated_at
    BEFORE UPDATE ON drivers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- تتبع مواقع السائقين
CREATE TABLE IF NOT EXISTS driver_locations (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID            NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    lat                 DECIMAL(10,8)   NOT NULL,
    lng                 DECIMAL(11,8)   NOT NULL,
    location            GEOGRAPHY(POINT, 4326),
    speed               DECIMAL(5,2),
    heading             DECIMAL(5,2),
    accuracy            DECIMAL(5,2),
    recorded_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  driver_locations IS 'سجل تتبع موقع السائقين';

CREATE INDEX IF NOT EXISTS idx_driver_locations_driver ON driver_locations(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_locations_recorded ON driver_locations(recorded_at DESC);

-- المناطق ورسوم التوصيل
CREATE TABLE IF NOT EXISTS zones (
    id                       UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    name_ar                  VARCHAR(100)   NOT NULL,
    name_en                  VARCHAR(100),
    city                     VARCHAR(100)   NOT NULL DEFAULT 'الإسكندرية',
    delivery_fee             DECIMAL(8,2)   NOT NULL DEFAULT 0.00,
    min_delivery_fee         DECIMAL(8,2)   NOT NULL DEFAULT 0.00,
    max_delivery_fee         DECIMAL(8,2),
    free_delivery_threshold  DECIMAL(10,2),
    estimated_minutes        INT            NOT NULL DEFAULT 30,
    polygon_coords           JSONB,
    is_active                BOOLEAN        NOT NULL DEFAULT TRUE,
    sort_order               INT            NOT NULL DEFAULT 0,
    created_at               TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  zones IS 'المناطق الجغرافية المخدومة';
COMMENT ON COLUMN zones.polygon_coords IS 'حدود المنطقة بصيغة GeoJSON';

DROP TRIGGER IF EXISTS trg_zones_updated_at ON zones;
CREATE TRIGGER trg_zones_updated_at
    BEFORE UPDATE ON zones
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- الجزء 2: المتاجر، الفئات، ساعات العمل، المنتجات، الخيارات والإضافات
CREATE TABLE IF NOT EXISTS stores (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name_ar             VARCHAR(200)    NOT NULL,
    name_en             VARCHAR(200),
    store_type          VARCHAR(50)     NOT NULL
                        CHECK (store_type IN ('restaurant','bakery','sweets','pharmacy',
                                              'fruits_vegetables','local_products','other')),
    logo_url            TEXT,
    cover_url           TEXT,
    description_ar      TEXT,
    description_en      TEXT,
    phone               VARCHAR(20)     NOT NULL,
    email               VARCHAR(255),
    address             TEXT            NOT NULL,
    lat                 DECIMAL(10,8)   NOT NULL,
    lng                 DECIMAL(11,8)   NOT NULL,
    location            GEOGRAPHY(POINT, 4326),
    delivery_radius     INT             NOT NULL DEFAULT 5000,
    min_order_amount    DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    delivery_fee        DECIMAL(8,2)    NOT NULL DEFAULT 0.00,
    free_delivery_threshold DECIMAL(10,2),
    opening_time        TIME,
    closing_time        TIME,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    is_verified         BOOLEAN         NOT NULL DEFAULT FALSE,
    rating              DECIMAL(3,2)    NOT NULL DEFAULT 0.00 CHECK (rating >= 0 AND rating <= 5),
    total_orders        INT             NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  stores IS 'المتاجر المسجلة على المنصة';
COMMENT ON COLUMN stores.store_type IS 'نوع المتجر';

CREATE INDEX IF NOT EXISTS idx_stores_type ON stores(store_type);
CREATE INDEX IF NOT EXISTS idx_stores_location ON stores USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_stores_is_active ON stores(is_active);

DROP TRIGGER IF EXISTS trg_stores_updated_at ON stores;
CREATE TRIGGER trg_stores_updated_at
    BEFORE UPDATE ON stores
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- فئات المنتجات
CREATE TABLE IF NOT EXISTS categories (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id            UUID            NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    parent_id           UUID            REFERENCES categories(id) ON DELETE CASCADE,
    name_ar             VARCHAR(100)    NOT NULL,
    name_en             VARCHAR(100),
    description_ar      TEXT,
    description_en      TEXT,
    icon_url            TEXT,
    image_url           TEXT,
    sort_order          INT             NOT NULL DEFAULT 0,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  categories IS 'فئات المنتجات داخل كل متجر';
COMMENT ON COLUMN categories.parent_id IS 'الفئة الأم (للفئات الفرعية)';

CREATE INDEX IF NOT EXISTS idx_categories_store ON categories(store_id);
CREATE INDEX IF NOT EXISTS idx_categories_parent ON categories(parent_id);

DROP TRIGGER IF EXISTS trg_categories_updated_at ON categories;
CREATE TRIGGER trg_categories_updated_at
    BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ساعات عمل المتاجر
CREATE TABLE IF NOT EXISTS store_hours (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id            UUID            NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    day_of_week         INT             NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    opening_time        TIME            NOT NULL,
    closing_time        TIME            NOT NULL,
    is_closed           BOOLEAN         NOT NULL DEFAULT FALSE,
    break_start         TIME,
    break_end           TIME,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    UNIQUE(store_id, day_of_week)
);

COMMENT ON TABLE  store_hours IS 'ساعات العمل الأسبوعية للمتاجر';

CREATE INDEX IF NOT EXISTS idx_store_hours_store ON store_hours(store_id);

DROP TRIGGER IF EXISTS trg_store_hours_updated_at ON store_hours;
CREATE TRIGGER trg_store_hours_updated_at
    BEFORE UPDATE ON store_hours
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- المنتجات
CREATE TABLE IF NOT EXISTS products (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id            UUID            NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    category_id         UUID            REFERENCES categories(id) ON DELETE SET NULL,
    name_ar             VARCHAR(200)    NOT NULL,
    name_en             VARCHAR(200),
    description_ar      TEXT,
    description_en      TEXT,
    price               DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    compare_price       DECIMAL(10,2),
    cost_per_item       DECIMAL(10,2),
    images              TEXT[]         DEFAULT '{}',
    unit                VARCHAR(20)     NOT NULL DEFAULT 'قطعة'
                        CHECK (unit IN ('قطعة','كجم','جرام','لتر','ملل','علبة','كيس','طبق','حبة','غير ذلك')),
    stock_quantity      INT             NOT NULL DEFAULT 0,
    is_featured         BOOLEAN         NOT NULL DEFAULT FALSE,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    is_available        BOOLEAN         NOT NULL DEFAULT TRUE,
    has_options         BOOLEAN         NOT NULL DEFAULT FALSE,
    has_addons          BOOLEAN         NOT NULL DEFAULT FALSE,
    prep_time_minutes   INT             NOT NULL DEFAULT 15,
    calories            INT,
    sort_order          INT             NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  products IS 'المنتجات المباعة في المتاجر';
COMMENT ON COLUMN products.images IS 'مصفوفة من روابط الصور';
COMMENT ON COLUMN products.stock_quantity IS 'الكمية المتوفرة في المخزون';

CREATE INDEX IF NOT EXISTS idx_products_store ON products(store_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active);

DROP TRIGGER IF EXISTS trg_products_updated_at ON products;
CREATE TRIGGER trg_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- خيارات المنتج
CREATE TABLE IF NOT EXISTS product_options (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id          UUID            NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    name_ar             VARCHAR(100)    NOT NULL,
    name_en             VARCHAR(100),
    option_type         VARCHAR(20)     NOT NULL DEFAULT 'single'
                        CHECK (option_type IN ('single','multiple')),
    is_required         BOOLEAN         NOT NULL DEFAULT FALSE,
    sort_order          INT             NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  product_options IS 'خيارات المنتج (مثل: الحجم، النوع)';

CREATE INDEX IF NOT EXISTS idx_product_options_product ON product_options(product_id);

DROP TRIGGER IF EXISTS trg_product_options_updated_at ON product_options;
CREATE TRIGGER trg_product_options_updated_at
    BEFORE UPDATE ON product_options
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- قيم الخيارات
CREATE TABLE IF NOT EXISTS option_values (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    option_id           UUID            NOT NULL REFERENCES product_options(id) ON DELETE CASCADE,
    value_ar            VARCHAR(100)    NOT NULL,
    value_en            VARCHAR(100),
    price_adjustment    DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    sort_order          INT             NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  option_values IS 'قيم خيارات المنتج (مثل: صغير، متوسط، كبير)';
COMMENT ON COLUMN option_values.price_adjustment IS 'تعديل السعر عن السعر الأساسي';

CREATE INDEX IF NOT EXISTS idx_option_values_option ON option_values(option_id);

DROP TRIGGER IF EXISTS trg_option_values_updated_at ON option_values;
CREATE TRIGGER trg_option_values_updated_at
    BEFORE UPDATE ON option_values
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- إضافات المنتج
CREATE TABLE IF NOT EXISTS product_addons (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id          UUID            NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    name_ar             VARCHAR(100)    NOT NULL,
    name_en             VARCHAR(100),
    price               DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    max_quantity        INT             NOT NULL DEFAULT 1,
    sort_order          INT             NOT NULL DEFAULT 0,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  product_addons IS 'إضافات المنتج (مثل: إضافات البيتزا)';

CREATE INDEX IF NOT EXISTS idx_product_addons_product ON product_addons(product_id);

DROP TRIGGER IF EXISTS trg_product_addons_updated_at ON product_addons;
CREATE TRIGGER trg_product_addons_updated_at
    BEFORE UPDATE ON product_addons
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- الجزء 3: عناوين التوصيل، عربة التسوق، الطلبات
CREATE TABLE IF NOT EXISTS addresses (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    label               VARCHAR(50)     NOT NULL,
    address_line        TEXT            NOT NULL,
    landmark            TEXT,
    city                VARCHAR(100)    NOT NULL DEFAULT 'الإسكندرية',
    district            VARCHAR(100),
    lat                 DECIMAL(10,8)   NOT NULL,
    lng                 DECIMAL(11,8)   NOT NULL,
    location            GEOGRAPHY(POINT, 4326),
    apartment_number    VARCHAR(20),
    floor_number        VARCHAR(20),
    extra_instructions  TEXT,
    is_default          BOOLEAN         NOT NULL DEFAULT FALSE,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  addresses IS 'عناوين التوصيل المحفوظة للمستخدمين';
COMMENT ON COLUMN addresses.label IS 'تسمية العنوان (المنزل، العمل، إلخ)';

CREATE INDEX IF NOT EXISTS idx_addresses_user ON addresses(user_id);
CREATE INDEX IF NOT EXISTS idx_addresses_location ON addresses USING GIST (location);

DROP TRIGGER IF EXISTS trg_addresses_updated_at ON addresses;
CREATE TRIGGER trg_addresses_updated_at
    BEFORE UPDATE ON addresses
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- عربة التسوق
CREATE TABLE IF NOT EXISTS carts (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_id            UUID            NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    product_id          UUID            NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    quantity            INT             NOT NULL DEFAULT 1,
    options_json        JSONB,
    addons_json         JSONB,
    unit_price          DECIMAL(10,2)   NOT NULL,
    total_price         DECIMAL(10,2)   NOT NULL,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  carts IS 'عربة التسوق المؤقتة للعملاء';

CREATE INDEX IF NOT EXISTS idx_carts_user ON carts(user_id);
CREATE INDEX IF NOT EXISTS idx_carts_store ON carts(store_id);

DROP TRIGGER IF EXISTS trg_carts_updated_at ON carts;
CREATE TRIGGER trg_carts_updated_at
    BEFORE UPDATE ON carts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- الطلبات
CREATE TABLE IF NOT EXISTS orders (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_id            UUID            NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    driver_id           UUID            REFERENCES drivers(id) ON DELETE SET NULL,
    address_id          UUID            NOT NULL REFERENCES addresses(id) ON DELETE CASCADE,
    status              VARCHAR(30)     NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','accepted','preparing','ready_for_delivery',
                                         'on_delivery','delivered','cancelled','rejected','refunded')),
    order_type          VARCHAR(20)     NOT NULL DEFAULT 'delivery'
                        CHECK (order_type IN ('delivery','pickup')),
    payment_method      VARCHAR(20)     NOT NULL
                        CHECK (payment_method IN ('cash','card','wallet')),
    payment_status      VARCHAR(20)     NOT NULL DEFAULT 'pending'
                        CHECK (payment_status IN ('pending','paid','failed','refunded')),
    subtotal            DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    delivery_fee        DECIMAL(8,2)    NOT NULL DEFAULT 0.00,
    service_fee         DECIMAL(8,2)    NOT NULL DEFAULT 0.00,
    tax_amount          DECIMAL(8,2)    NOT NULL DEFAULT 0.00,
    discount_amount     DECIMAL(8,2)    NOT NULL DEFAULT 0.00,
    total_amount        DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    driver_tip          DECIMAL(8,2)    NOT NULL DEFAULT 0.00,
    notes               TEXT,
    delivery_notes      TEXT,
    expected_delivery_time TIMESTAMPTZ,
    actual_delivery_time TIMESTAMPTZ,
    accepted_at         TIMESTAMPTZ,
    prepared_at         TIMESTAMPTZ,
    picked_up_at        TIMESTAMPTZ,
    cancelled_at        TIMESTAMPTZ,
    cancellation_reason TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  orders IS 'الطلبات المقدمة من العملاء';
COMMENT ON COLUMN orders.status IS 'حالة الطلب';

CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_store ON orders(store_id);
CREATE INDEX IF NOT EXISTS idx_orders_driver ON orders(driver_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at);

DROP TRIGGER IF EXISTS trg_orders_updated_at ON orders;
CREATE TRIGGER trg_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- عناصر الطلب
CREATE TABLE IF NOT EXISTS order_items (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id            UUID            NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id          UUID            NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    product_name_ar     VARCHAR(200)    NOT NULL,
    product_name_en     VARCHAR(200),
    quantity            INT             NOT NULL DEFAULT 1,
    unit_price          DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    total_price         DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    options_json        JSONB,
    addons_json         JSONB,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  order_items IS 'عناصر الطلب (المنتجات المطلوبة)';
COMMENT ON COLUMN order_items.options_json IS 'الخيارات المختارة للمنتج';
COMMENT ON COLUMN order_items.addons_json IS 'الإضافات المختارة للمنتج';

CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id);

-- الجزء 4: المدفوعات، التقييمات، الكوبونات، الإشعارات
CREATE TABLE IF NOT EXISTS payments (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id            UUID            NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    user_id             UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount              DECIMAL(10,2)   NOT NULL,
    payment_method      VARCHAR(20)     NOT NULL
                        CHECK (payment_method IN ('cash','card','wallet')),
    payment_status      VARCHAR(20)     NOT NULL DEFAULT 'pending'
                        CHECK (payment_status IN ('pending','successful','failed','refunded')),
    transaction_id      VARCHAR(255),
    gateway             VARCHAR(50),
    gateway_response    JSONB,
    paid_at             TIMESTAMPTZ,
    refunded_at         TIMESTAMPTZ,
    refund_amount       DECIMAL(10,2),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  payments IS 'معاملات الدفع للطلبات';
COMMENT ON COLUMN payments.gateway_response IS 'الاستجابة الكاملة من بوابة الدفع';

CREATE INDEX IF NOT EXISTS idx_payments_order ON payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_user ON payments(user_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(payment_status);

DROP TRIGGER IF EXISTS trg_payments_updated_at ON payments;
CREATE TRIGGER trg_payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- التقييمات والمراجعات
CREATE TABLE IF NOT EXISTS reviews (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id            UUID            NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    user_id             UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_id            UUID            REFERENCES stores(id) ON DELETE CASCADE,
    driver_id           UUID            REFERENCES drivers(id) ON DELETE CASCADE,
    rating              INT             NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment             TEXT,
    review_type         VARCHAR(20)     NOT NULL
                        CHECK (review_type IN ('store','driver','product')),
    target_id           UUID            NOT NULL,
    images              TEXT[]         DEFAULT '{}',
    is_verified         BOOLEAN         NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  reviews IS 'التقييمات والمراجعات من العملاء';
COMMENT ON COLUMN reviews.review_type IS 'نوع المراجعة: store=متجر، driver=سائق، product=منتج';
COMMENT ON COLUMN reviews.target_id IS 'معرف المستهدف حسب review_type';

CREATE INDEX IF NOT EXISTS idx_reviews_order ON reviews(order_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user ON reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_store ON reviews(store_id);
CREATE INDEX IF NOT EXISTS idx_reviews_driver ON reviews(driver_id);
CREATE INDEX IF NOT EXISTS idx_reviews_target ON reviews(review_type, target_id);

DROP TRIGGER IF EXISTS trg_reviews_updated_at ON reviews;
CREATE TRIGGER trg_reviews_updated_at
    BEFORE UPDATE ON reviews
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- أكواد الخصم
CREATE TABLE IF NOT EXISTS coupons (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    code                VARCHAR(50)     NOT NULL UNIQUE,
    type                VARCHAR(20)     NOT NULL
                        CHECK (type IN ('percentage','fixed')),
    value               DECIMAL(10,2)   NOT NULL,
    min_order_amount    DECIMAL(10,2),
    max_discount        DECIMAL(10,2),
    store_id            UUID            REFERENCES stores(id) ON DELETE CASCADE,
    valid_from          TIMESTAMPTZ     NOT NULL,
    valid_until         TIMESTAMPTZ     NOT NULL,
    usage_limit         INT,
    used_count          INT             NOT NULL DEFAULT 0,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  coupons IS 'أكواد الخصم والعروض الترويجية';

CREATE INDEX IF NOT EXISTS idx_coupons_code ON coupons(code);
CREATE INDEX IF NOT EXISTS idx_coupons_valid ON coupons(valid_from, valid_until);

DROP TRIGGER IF EXISTS trg_coupons_updated_at ON coupons;
CREATE TRIGGER trg_coupons_updated_at
    BEFORE UPDATE ON coupons
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- استخدامات أكواد الخصم
CREATE TABLE IF NOT EXISTS coupon_usages (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    coupon_id           UUID            NOT NULL REFERENCES coupons(id) ON DELETE CASCADE,
    order_id            UUID            NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    user_id             UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    discount_amount     DECIMAL(10,2)   NOT NULL,
    used_at             TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  coupon_usages IS 'سجل استخدامات أكواد الخصم';

CREATE INDEX IF NOT EXISTS idx_coupon_usages_coupon ON coupon_usages(coupon_id);
CREATE INDEX IF NOT EXISTS idx_coupon_usages_order ON coupon_usages(order_id);

-- الإشعارات
CREATE TABLE IF NOT EXISTS notifications (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type                VARCHAR(50)     NOT NULL
                        CHECK (type IN ('order_status','promotion','payment','system','driver')),
    title_ar            VARCHAR(200)    NOT NULL,
    title_en            VARCHAR(200),
    body_ar             TEXT            NOT NULL,
    body_en             TEXT,
    data                JSONB,
    is_read             BOOLEAN         NOT NULL DEFAULT FALSE,
    read_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  notifications IS 'إشعارات المستخدمين';
COMMENT ON COLUMN notifications.data IS 'بيانات إضافية مرتبطة بالإشعار';

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);
