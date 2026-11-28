-- 0. CLEAN UP EXISTING OBJECTS (safe to re-run)
DROP VIEW IF EXISTS public.view_portfolio_kpis CASCADE;
DROP VIEW IF EXISTS public.view_employee_leaderboard CASCADE;
DROP TRIGGER IF EXISTS trg_auto_award_module_xp ON public.module_assignments;
DROP TRIGGER IF EXISTS trg_module_assignment_progress ON public.module_assignments;
DROP TRIGGER IF EXISTS trg_proj_module_progress ON public.project_modules;
DROP FUNCTION IF EXISTS public.fn_auto_award_module_xp() CASCADE;
DROP FUNCTION IF EXISTS public.fn_recalculate_project_progress() CASCADE;
DROP TABLE IF EXISTS public.helpdesk_tickets CASCADE;
DROP TABLE IF EXISTS public.payroll_records CASCADE;
DROP TABLE IF EXISTS public.leave_requests CASCADE;
DROP TABLE IF EXISTS public.attendance CASCADE;
DROP TABLE IF EXISTS public.xp_transactions CASCADE;
DROP TABLE IF EXISTS public.module_assignments CASCADE;
DROP TABLE IF EXISTS public.project_modules CASCADE;
DROP TABLE IF EXISTS public.project_members CASCADE;
DROP TABLE IF EXISTS public.projects CASCADE;
DROP TABLE IF EXISTS public.executive_approvals CASCADE;
DROP TABLE IF EXISTS public.bulletins CASCADE;
DROP TABLE IF EXISTS public.employees CASCADE;
DROP TYPE IF EXISTS user_role CASCADE;
DROP TYPE IF EXISTS project_status CASCADE;
DROP TYPE IF EXISTS project_priority CASCADE;
DROP TYPE IF EXISTS attendance_status CASCADE;
DROP TYPE IF EXISTS leave_status CASCADE;
DROP TYPE IF EXISTS payroll_status CASCADE;
DROP TYPE IF EXISTS ticket_priority CASCADE;

-- 0B. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. ENUMS & DOMAIN TYPES
-- ============================================================================
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('ceo', 'manager', 'lead', 'employee', 'intern');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE project_status AS ENUM ('Draft', 'Active', 'In Review', 'Completed', 'Archived');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE project_priority AS ENUM ('Low', 'Medium', 'High', 'Critical');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE attendance_status AS ENUM ('Present', 'Late', 'Half Day', 'Absent', 'On Leave');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE leave_status AS ENUM ('Pending', 'Approved', 'Rejected', 'Cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE payroll_status AS ENUM ('Unpaid', 'Processing', 'Paid', 'On Hold');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE ticket_priority AS ENUM ('Low', 'Normal', 'Urgent', 'Emergency');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- 2. EMPLOYEES & PROFILES TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    name VARCHAR(120) NOT NULL,
    email VARCHAR(160) UNIQUE NOT NULL,
    role user_role DEFAULT 'employee' NOT NULL,
    designation VARCHAR(100) DEFAULT 'Software Specialist',
    department VARCHAR(100) DEFAULT 'Engineering',
    phone VARCHAR(30),
    joined_date DATE DEFAULT CURRENT_DATE NOT NULL,
    badge VARCHAR(40) DEFAULT 'CORE',
    annual_ctc VARCHAR(50) DEFAULT '₹12,00,000',
    monthly_package VARCHAR(50) DEFAULT '₹1,00,000',

    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================================
-- 3. EXECUTIVE DIRECTIVES, ANNOUNCEMENTS & BULLETINS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.bulletins (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    category VARCHAR(60) DEFAULT 'EXECUTIVE DIRECTIVE',
    tag VARCHAR(30) DEFAULT 'OPERATIONS',
    author_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    author_name VARCHAR(120) DEFAULT 'Office of the CEO',
    is_pinned BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================================
-- 4. EXECUTIVE APPROVALS QUEUE (CEO DECISION QUEUE)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.executive_approvals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(80) DEFAULT 'Budget Authorization',
    requested_amount VARCHAR(50),
    submitted_by UUID REFERENCES public.employees(id) ON DELETE CASCADE,
    submitter_title VARCHAR(100),
    status VARCHAR(30) DEFAULT 'Pending',
    ceo_remarks TEXT,
    decided_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================================
-- 5. PROJECTS TABLE (PORTFOLIO, AMOUNTS & PROGRESS)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(200) NOT NULL,
    description TEXT,
    icon VARCHAR(12) DEFAULT '🚀',
    icon_bg VARCHAR(20) DEFAULT '#eff6ff',
    icon_color VARCHAR(20) DEFAULT '#2563eb',
    start_date DATE DEFAULT CURRENT_DATE NOT NULL,
    deadline DATE,
    amount VARCHAR(50) DEFAULT '₹0',
    status project_status DEFAULT 'Active' NOT NULL,
    priority project_priority DEFAULT 'Medium' NOT NULL,
    priority_color VARCHAR(20) DEFAULT '#f59e0b',
    progress INT DEFAULT 0 CHECK (progress >= 0 AND progress <= 100),
    total_modules INT DEFAULT 0,
    completed_modules INT DEFAULT 0,
    completed_at TIMESTAMPTZ,
    created_by_email VARCHAR(160) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================================
-- 6. PROJECT MEMBERS (TEAM ROSTER)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.project_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    assigned_by VARCHAR(160) NOT NULL,
    assigned_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CONSTRAINT uq_proj_employee UNIQUE (project_id, employee_id)
);

-- ============================================================================
-- 7. PROJECT MODULES (DELIVERABLES / TASKS)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.project_modules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    xp_reward INT DEFAULT 50 CHECK (xp_reward >= 0),
    deadline DATE,
    sort_order INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================================
-- 8. MODULE ASSIGNMENTS (CHECKLISTS & COMPLETIONS)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.module_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    module_id UUID NOT NULL REFERENCES public.project_modules(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    is_completed BOOLEAN DEFAULT FALSE NOT NULL,
    completed_at TIMESTAMPTZ,
    completed_by UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    assigned_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CONSTRAINT uq_module_employee UNIQUE (module_id, employee_id)
);

-- ============================================================================
-- 9. GAMIFICATION & XP TRANSACTIONS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.xp_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    project_id UUID REFERENCES public.projects(id) ON DELETE SET NULL,
    module_id UUID REFERENCES public.project_modules(id) ON DELETE SET NULL,
    amount INT NOT NULL,
    reason VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================================
-- 10. ATTENDANCE & SHIFT VERIFICATION LOGS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.attendance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    attendance_date DATE DEFAULT CURRENT_DATE NOT NULL,
    check_in_time TIME DEFAULT CURRENT_TIME,
    check_out_time TIME,
    status attendance_status DEFAULT 'Present' NOT NULL,
    verified_by_swipe BOOLEAN DEFAULT TRUE,
    work_location VARCHAR(50) DEFAULT 'HQ Office',
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CONSTRAINT uq_emp_daily_attendance UNIQUE (employee_id, attendance_date)
);

-- ============================================================================
-- 11. LEAVE APPLICATIONS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.leave_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    leave_type VARCHAR(60) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    total_days INT DEFAULT 1 NOT NULL,
    reason TEXT NOT NULL,
    status leave_status DEFAULT 'Pending' NOT NULL,
    reviewed_by UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    review_remarks TEXT,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================================
-- 12. PAYROLL & SALARY DISBURSEMENTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.payroll_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    payout_month VARCHAR(20) NOT NULL,
    salary_cycle_year INT NOT NULL,
    salary_cycle_month INT NOT NULL,
    gross_amount NUMERIC(12,2) NOT NULL,
    deductions NUMERIC(12,2) DEFAULT 0.00,
    net_payout NUMERIC(12,2) NOT NULL,
    status payroll_status DEFAULT 'Unpaid' NOT NULL,
    paid_at TIMESTAMPTZ,
    transaction_ref VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CONSTRAINT uq_emp_payroll_cycle UNIQUE (employee_id, salary_cycle_year, salary_cycle_month)
);

-- ============================================================================
-- 13. HELPDESK & INTERNAL TICKETING
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.helpdesk_tickets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_number VARCHAR(20) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    priority ticket_priority DEFAULT 'Normal' NOT NULL,
    status VARCHAR(30) DEFAULT 'Open' NOT NULL,
    created_by UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    assigned_to UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    resolution_notes TEXT,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================================
-- 14. AUTOMATION TRIGGERS & BUSINESS LOGIC
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_recalculate_project_progress()
RETURNS TRIGGER AS $$
DECLARE
    _project_id UUID;
    _total_mods INT;
    _completed_mods INT;
    _progress_pct INT;
BEGIN
    _project_id := COALESCE(NEW.project_id, OLD.project_id);

    SELECT COUNT(*) INTO _total_mods
    FROM public.project_modules
    WHERE project_id = _project_id;

    SELECT COUNT(DISTINCT m.id) INTO _completed_mods
    FROM public.project_modules m
    WHERE m.project_id = _project_id
      AND EXISTS (SELECT 1 FROM public.module_assignments ma WHERE ma.module_id = m.id)
      AND NOT EXISTS (SELECT 1 FROM public.module_assignments ma WHERE ma.module_id = m.id AND ma.is_completed = FALSE);

    IF _total_mods > 0 THEN
        _progress_pct := ROUND((_completed_mods::NUMERIC / _total_mods::NUMERIC) * 100);
    ELSE
        _progress_pct := 0;
    END IF;

    UPDATE public.projects
    SET total_modules = _total_mods,
        completed_modules = _completed_mods,
        progress = _progress_pct,
        status = CASE 
            WHEN _total_mods > 0 AND _completed_mods = _total_mods THEN 'Completed'::project_status
            WHEN status = 'Completed'::project_status THEN 'Active'::project_status
            ELSE status
        END,
        completed_at = CASE 
            WHEN _total_mods > 0 AND _completed_mods = _total_mods THEN NOW()
            ELSE NULL
        END,
        updated_at = NOW()
    WHERE id = _project_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_proj_module_progress ON public.project_modules;
CREATE TRIGGER trg_proj_module_progress
AFTER INSERT OR UPDATE OR DELETE ON public.project_modules
FOR EACH ROW EXECUTE FUNCTION public.fn_recalculate_project_progress();

DROP TRIGGER IF EXISTS trg_module_assignment_progress ON public.module_assignments;
CREATE TRIGGER trg_module_assignment_progress
AFTER INSERT OR UPDATE OR DELETE ON public.module_assignments
FOR EACH ROW EXECUTE FUNCTION public.fn_recalculate_project_progress();

CREATE OR REPLACE FUNCTION public.fn_auto_award_module_xp()
RETURNS TRIGGER AS $$
DECLARE
    _reward INT;
    _module_title VARCHAR(255);
BEGIN
    IF NEW.is_completed = TRUE AND (OLD.is_completed IS NULL OR OLD.is_completed = FALSE) THEN
        SELECT xp_reward, title INTO _reward, _module_title
        FROM public.project_modules
        WHERE id = NEW.module_id;

        INSERT INTO public.xp_transactions (employee_id, project_id, module_id, amount, reason)
        VALUES (
            NEW.employee_id,
            NEW.project_id,
            NEW.module_id,
            COALESCE(_reward, 50),
            'Completed Deliverable: ' || COALESCE(_module_title, 'Module Task')
        );
    ELSIF NEW.is_completed = FALSE AND OLD.is_completed = TRUE THEN
        DELETE FROM public.xp_transactions
        WHERE module_id = NEW.module_id AND employee_id = NEW.employee_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_award_module_xp ON public.module_assignments;
CREATE TRIGGER trg_auto_award_module_xp
AFTER UPDATE ON public.module_assignments
FOR EACH ROW EXECUTE FUNCTION public.fn_auto_award_module_xp();

-- ============================================================================
-- 15. COMPUTED VIEWS FOR CLIENT DASHBOARDS
-- ============================================================================

CREATE OR REPLACE VIEW public.view_employee_leaderboard AS
SELECT 
    e.id AS employee_id,
    e.name,
    e.email,
    e.role,
    e.designation,
    e.department,
    COALESCE(SUM(xt.amount), 0)::INT AS total_xp,
    CASE 
        WHEN COALESCE(SUM(xt.amount), 0) >= 2000 THEN 'Master Lead'
        WHEN COALESCE(SUM(xt.amount), 0) >= 1000 THEN 'Architect'
        WHEN COALESCE(SUM(xt.amount), 0) >= 500  THEN 'Specialist'
        WHEN COALESCE(SUM(xt.amount), 0) >= 200  THEN 'Builder'
        ELSE 'Rookie'
    END AS rank_title,
    CASE 
        WHEN COALESCE(SUM(xt.amount), 0) >= 2000 THEN '👑'
        WHEN COALESCE(SUM(xt.amount), 0) >= 1000 THEN '🏛'
        WHEN COALESCE(SUM(xt.amount), 0) >= 500  THEN '⚡'
        WHEN COALESCE(SUM(xt.amount), 0) >= 200  THEN '🛠'
        ELSE '🌱'
    END AS rank_icon,
    COUNT(DISTINCT ma.id) FILTER (WHERE ma.is_completed = TRUE) AS completed_deliverables_count
FROM public.employees e
LEFT JOIN public.xp_transactions xt ON e.id = xt.employee_id
LEFT JOIN public.module_assignments ma ON e.id = ma.employee_id
WHERE e.is_active = TRUE
GROUP BY e.id, e.name, e.email, e.role, e.designation, e.department
ORDER BY total_xp DESC;

CREATE OR REPLACE VIEW public.view_portfolio_kpis AS
SELECT
    COUNT(p.id) AS total_projects,
    COUNT(p.id) FILTER (WHERE p.status = 'Completed') AS completed_projects,
    COUNT(p.id) FILTER (WHERE p.status = 'Active') AS active_projects,
    COALESCE(SUM(p.total_modules), 0) AS total_modules,
    COALESCE(SUM(p.completed_modules), 0) AS completed_modules,
    (SELECT COUNT(*) FROM public.employees WHERE is_active = TRUE) AS active_headcount,
    COALESCE((SELECT SUM(amount) FROM public.xp_transactions), 0) AS total_organization_xp
FROM public.projects p;

-- ============================================================================
-- 16. ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.module_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.xp_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bulletins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.executive_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.helpdesk_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow authenticated read employees" ON public.employees FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow authenticated read projects" ON public.projects FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow authenticated read project_members" ON public.project_members FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow authenticated read project_modules" ON public.project_modules FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow authenticated read module_assignments" ON public.module_assignments FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow authenticated read xp_transactions" ON public.xp_transactions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow authenticated read attendance" ON public.attendance FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow authenticated read leave_requests" ON public.leave_requests FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow authenticated read bulletins" ON public.bulletins FOR SELECT TO authenticated USING (true);

CREATE POLICY "Allow employees insert own attendance" ON public.attendance 
FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Allow employees update assignments" ON public.module_assignments 
FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Allow employees submit leave" ON public.leave_requests 
FOR INSERT TO authenticated WITH CHECK (true);

-- ============================================================================
-- 17. SEED DATA REMOVED (Add your own real data via Supabase dashboard)
-- ============================================================================
