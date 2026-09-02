-- Enable PostGIS for location distance calculation and UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 1. ENUMS
CREATE TYPE user_role AS ENUM ('admin', 'supervisor', 'tom_operator');
CREATE TYPE punch_status AS ENUM ('in_progress', 'completed', 'unassigned_pending', 'rejected', 'auto_absent');
CREATE TYPE attendance_status AS ENUM ('present', 'absent', 'pending');
CREATE TYPE platform_type AS ENUM ('android', 'ios', 'pwa');

-- 2. ORGANIZATIONS (TENANTS)
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. USER PROFILES
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    role user_role NOT NULL,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    biometric_id VARCHAR(100),
    company_id VARCHAR(100),
    bmrcl_id VARCHAR(100),
    face_embedding JSONB,
    pin_hash VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. STATIONS & TOM OPERATING SYSTEMS
CREATE TABLE stations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    supervisor_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    punch_radius_meters INTEGER DEFAULT 600,
    default_fixed_amount NUMERIC(10, 2) DEFAULT 700.00,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE station_operating_systems (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    station_id UUID REFERENCES stations(id) ON DELETE CASCADE,
    system_name VARCHAR(100) NOT NULL, -- e.g., 'TOM 01'
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. SHIFTS & ROSTER ASSIGNMENTS
CREATE TABLE shifts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    station_id UUID REFERENCES stations(id) ON DELETE CASCADE,
    supervisor_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    shift_name VARCHAR(100) NOT NULL, -- e.g., 'A Shift'
    duty_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    daily_amount NUMERIC(10, 2) NOT NULL DEFAULT 700.00,
    is_published BOOLEAN DEFAULT FALSE,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE shift_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    shift_id UUID REFERENCES shifts(id) ON DELETE CASCADE,
    station_id UUID REFERENCES stations(id) ON DELETE CASCADE,
    operating_system_id UUID REFERENCES station_operating_systems(id) ON DELETE SET NULL,
    operator_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    is_ot BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(shift_id, operating_system_id)
);

-- 6. PUNCH SESSIONS & ATTENDANCE
CREATE TABLE punch_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    operator_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    station_id UUID REFERENCES stations(id) ON DELETE SET NULL,
    shift_id UUID REFERENCES shifts(id) ON DELETE SET NULL,
    duty_date DATE NOT NULL, -- Anchored to punch-in date
    punch_in_at TIMESTAMPTZ NOT NULL,
    punch_in_lat DOUBLE PRECISION NOT NULL,
    punch_in_lng DOUBLE PRECISION NOT NULL,
    punch_in_verified BOOLEAN DEFAULT FALSE,
    punch_out_at TIMESTAMPTZ,
    punch_out_lat DOUBLE PRECISION,
    punch_out_lng DOUBLE PRECISION,
    punch_out_verified BOOLEAN DEFAULT FALSE,
    status punch_status DEFAULT 'in_progress',
    supervisor_approval_id UUID REFERENCES profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE attendance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    operator_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    station_id UUID REFERENCES stations(id) ON DELETE SET NULL,
    shift_id UUID REFERENCES shifts(id) ON DELETE SET NULL,
    punch_session_id UUID REFERENCES punch_sessions(id) ON DELETE SET NULL,
    duty_date DATE NOT NULL,
    status attendance_status DEFAULT 'present',
    is_ot BOOLEAN DEFAULT FALSE,
    earnings NUMERIC(10, 2) DEFAULT 0.00,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. NOTIFICATIONS & DEVICE TOKENS
CREATE TABLE device_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL UNIQUE,
    platform platform_type NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    body TEXT NOT NULL,
    payload JSONB,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. APP RELEASES & AUDIT LOGS
CREATE TABLE app_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    platform platform_type NOT NULL,
    version VARCHAR(50) NOT NULL,
    min_supported_version VARCHAR(50) NOT NULL,
    update_url TEXT NOT NULL,
    description TEXT,
    is_mandatory BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    action VARCHAR(255) NOT NULL,
    target_table VARCHAR(100),
    target_id UUID,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- INDEXES FOR PERFORMANCE & ALPHABETICAL SORTING
CREATE INDEX idx_profiles_org_name ON profiles (org_id, full_name ASC);
CREATE INDEX idx_shifts_date_station ON shifts (duty_date, station_id);
CREATE INDEX idx_punch_sessions_operator_date ON punch_sessions (operator_id, duty_date);
CREATE INDEX idx_attendance_date_station ON attendance (duty_date, station_id);