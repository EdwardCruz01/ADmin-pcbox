-- PC BOX | Instalación completa de producción
-- Ejecutar UNA sola vez en Supabase > SQL Editor sobre un proyecto vacío.
-- Crea el esquema, seguridad, sorteo inicial a S/ 5 y asigna admin a
-- pcbox1508@gmail.com. Crea primero ese correo en Authentication > Users.
-- La contraseña no se almacena aquí: configúrala únicamente en Supabase Auth.

BEGIN;

DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'user');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text,
  email text,
  phone text,
  notify boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, phone)
  VALUES (NEW.id, NEW.raw_user_meta_data->>'full_name', NEW.email, NEW.raw_user_meta_data->>'phone')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TABLE IF NOT EXISTS public.raffles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text,
  details text,
  image_url text,
  ticket_price numeric(10,2) NOT NULL DEFAULT 5,
  status text NOT NULL DEFAULT 'activo',
  draw_date timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.prizes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raffle_id uuid NOT NULL REFERENCES public.raffles(id) ON DELETE CASCADE,
  position int NOT NULL DEFAULT 1,
  name text NOT NULL,
  image_url text,
  winner_ticket_number int,
  winner_name text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.registrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raffle_id uuid NOT NULL REFERENCES public.raffles(id) ON DELETE CASCADE,
  dni text NOT NULL,
  full_name text NOT NULL,
  birth_date date,
  phone text,
  email text,
  quantity int NOT NULL DEFAULT 1,
  amount numeric(10,2) NOT NULL DEFAULT 0,
  receipt_url text,
  status text NOT NULL DEFAULT 'pendiente',
  admin_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz
);
CREATE INDEX IF NOT EXISTS registrations_dni_idx ON public.registrations (dni);

CREATE TABLE IF NOT EXISTS public.tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raffle_id uuid NOT NULL REFERENCES public.raffles(id) ON DELETE CASCADE,
  registration_id uuid NOT NULL REFERENCES public.registrations(id) ON DELETE CASCADE,
  number int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (raffle_id, number)
);

CREATE TABLE IF NOT EXISTS public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  price numeric(10,2),
  old_price numeric(10,2),
  image_url text,
  tag text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.notification_subscribers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL CHECK (char_length(full_name) BETWEEN 2 AND 120),
  email text,
  phone text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT notification_subscribers_contact_check CHECK (email IS NOT NULL OR phone IS NOT NULL)
);
CREATE UNIQUE INDEX IF NOT EXISTS notification_subscribers_email_uidx
  ON public.notification_subscribers (lower(email)) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS notification_subscribers_phone_uidx
  ON public.notification_subscribers (phone) WHERE phone IS NOT NULL;

GRANT SELECT ON public.raffles, public.prizes, public.tickets, public.products TO anon, authenticated;
GRANT SELECT ON public.user_roles TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT, UPDATE ON public.registrations TO authenticated;
GRANT ALL ON public.user_roles, public.profiles, public.raffles, public.prizes,
  public.registrations, public.tickets, public.products, public.notification_subscribers TO service_role;
REVOKE ALL ON public.notification_subscribers FROM anon, authenticated;

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.raffles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prizes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_subscribers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own roles readable" ON public.user_roles;
CREATE POLICY "own roles readable" ON public.user_roles FOR SELECT TO authenticated
USING (user_id = auth.uid());
DROP POLICY IF EXISTS "own profile select" ON public.profiles;
CREATE POLICY "own profile select" ON public.profiles FOR SELECT TO authenticated USING (id = auth.uid());
DROP POLICY IF EXISTS "own profile insert" ON public.profiles;
CREATE POLICY "own profile insert" ON public.profiles FOR INSERT TO authenticated WITH CHECK (id = auth.uid());
DROP POLICY IF EXISTS "own profile update" ON public.profiles;
CREATE POLICY "own profile update" ON public.profiles FOR UPDATE TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "raffles public read" ON public.raffles;
CREATE POLICY "raffles public read" ON public.raffles FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "raffles admin write" ON public.raffles;
CREATE POLICY "raffles admin write" ON public.raffles FOR ALL TO authenticated
USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));
DROP POLICY IF EXISTS "prizes public read" ON public.prizes;
CREATE POLICY "prizes public read" ON public.prizes FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "prizes admin write" ON public.prizes;
CREATE POLICY "prizes admin write" ON public.prizes FOR ALL TO authenticated
USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));
DROP POLICY IF EXISTS "registrations admin all" ON public.registrations;
CREATE POLICY "registrations admin all" ON public.registrations FOR ALL TO authenticated
USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));
DROP POLICY IF EXISTS "tickets public read" ON public.tickets;
CREATE POLICY "tickets public read" ON public.tickets FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "tickets admin write" ON public.tickets;
CREATE POLICY "tickets admin write" ON public.tickets FOR ALL TO authenticated
USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));
DROP POLICY IF EXISTS "products public read" ON public.products;
CREATE POLICY "products public read" ON public.products FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "products admin write" ON public.products;
CREATE POLICY "products admin write" ON public.products FOR ALL TO authenticated
USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('comprobantes', 'comprobantes', false, 10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']::text[])
ON CONFLICT (id) DO UPDATE SET public = false, file_size_limit = 10485760,
  allowed_mime_types = EXCLUDED.allowed_mime_types;
DROP POLICY IF EXISTS "comprobantes upload" ON storage.objects;
CREATE POLICY "comprobantes upload" ON storage.objects FOR INSERT TO anon, authenticated
WITH CHECK (bucket_id = 'comprobantes'
  AND name ~ '^\d{8}/[a-fA-F0-9-]{8,64}\.(jpg|jpeg|png|webp|heic|pdf)$'
  AND COALESCE((metadata->>'mimetype') IN ('image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf'), false));
DROP POLICY IF EXISTS "comprobantes admin read" ON storage.objects;
CREATE POLICY "comprobantes admin read" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'comprobantes' AND public.has_role(auth.uid(), 'admin'));
DROP POLICY IF EXISTS "comprobantes admin delete" ON storage.objects;
CREATE POLICY "comprobantes admin delete" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'comprobantes' AND public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.aprobar_inscripcion(p_registration_id uuid, p_nota text DEFAULT NULL)
RETURNS TABLE (registration_id uuid, numbers int[]) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_reg public.registrations%ROWTYPE; v_next int; v_nums int[]; v_existing_numbers int[]; i int;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT r.* INTO v_reg FROM public.registrations AS r WHERE r.id = p_registration_id FOR UPDATE;
  IF v_reg.id IS NULL THEN RAISE EXCEPTION 'La inscripción no existe'; END IF;
  IF v_reg.status = 'rechazado' THEN RAISE EXCEPTION 'No se puede aprobar una inscripción rechazada'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_reg.raffle_id::text, 0));
  SELECT array_agg(t.number ORDER BY t.number) INTO v_existing_numbers FROM public.tickets AS t WHERE t.registration_id = p_registration_id;
  IF v_existing_numbers IS NOT NULL THEN
    RETURN QUERY SELECT p_registration_id, v_existing_numbers;
    RETURN;
  END IF;
  SELECT COALESCE(MAX(t.number) + 1, 100) INTO v_next FROM public.tickets AS t WHERE t.raffle_id = v_reg.raffle_id;
  v_nums := ARRAY[]::int[];
  FOR i IN 0 .. (v_reg.quantity - 1) LOOP
    INSERT INTO public.tickets (raffle_id, registration_id, number) VALUES (v_reg.raffle_id, v_reg.id, v_next + i);
    v_nums := array_append(v_nums, v_next + i);
  END LOOP;
  UPDATE public.registrations AS r SET status = 'aprobado', admin_note = COALESCE(p_nota, r.admin_note), reviewed_at = now() WHERE r.id = p_registration_id;
  RETURN QUERY SELECT p_registration_id, v_nums;
END; $$;

CREATE OR REPLACE FUNCTION public.rechazar_inscripcion(p_registration_id uuid, p_nota text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'No autorizado'; END IF;
  UPDATE public.registrations SET status = 'rechazado', admin_note = COALESCE(p_nota, admin_note), reviewed_at = now() WHERE id = p_registration_id;
END; $$;

CREATE OR REPLACE FUNCTION public.eliminar_inscripcion(p_registration_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'No autorizado'; END IF;
  DELETE FROM public.registrations WHERE id = p_registration_id;
END; $$;

CREATE OR REPLACE FUNCTION public.sortear_ganador(p_prize_id uuid)
RETURNS TABLE (ticket_number int, winner_name text) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_prize public.prizes%ROWTYPE; v_number int; v_name text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_prize FROM public.prizes WHERE id = p_prize_id FOR UPDATE;
  IF v_prize.id IS NULL THEN RAISE EXCEPTION 'El premio no existe'; END IF;
  IF v_prize.winner_ticket_number IS NOT NULL THEN RAISE EXCEPTION 'Este premio ya tiene ganador'; END IF;
  SELECT t.number, r.full_name INTO v_number, v_name FROM public.tickets t
  JOIN public.registrations r ON r.id = t.registration_id
  WHERE t.raffle_id = v_prize.raffle_id AND r.status = 'aprobado'
    AND NOT EXISTS (SELECT 1 FROM public.prizes p WHERE p.raffle_id = v_prize.raffle_id AND p.winner_ticket_number = t.number)
  ORDER BY random() LIMIT 1;
  IF v_number IS NULL THEN RAISE EXCEPTION 'No hay tickets aprobados disponibles'; END IF;
  UPDATE public.prizes SET winner_ticket_number = v_number, winner_name = v_name WHERE id = p_prize_id;
  RETURN QUERY SELECT v_number, v_name;
END; $$;

REVOKE ALL ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.aprobar_inscripcion(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rechazar_inscripcion(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.eliminar_inscripcion(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sortear_ganador(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.aprobar_inscripcion(uuid, text), public.rechazar_inscripcion(uuid, text), public.eliminar_inscripcion(uuid), public.sortear_ganador(uuid) TO authenticated;

-- Sorteo inicial y premios. Si ya existe por título, no duplica datos.
DO $$ DECLARE v_raffle uuid;
BEGIN
  SELECT id INTO v_raffle FROM public.raffles WHERE title = 'Gran Sorteo Laptop Gamer ASUS ROG' LIMIT 1;
  IF v_raffle IS NULL THEN
    INSERT INTO public.raffles (title, description, details, ticket_price, status, draw_date)
    VALUES ('Gran Sorteo Laptop Gamer ASUS ROG', 'Participa por una laptop gamer de última generación y más premios tecnológicos.', 'Sorteo con 5 premios. Cada ticket cuesta S/ 5. La inscripción se valida tras la aprobación del comprobante de Yape.', 5, 'activo', now() + interval '20 days') RETURNING id INTO v_raffle;
    INSERT INTO public.prizes (raffle_id, position, name) VALUES
      (v_raffle, 1, 'Laptop Gamer ASUS ROG RTX 4060'),
      (v_raffle, 2, 'Monitor Gamer 27" 165Hz'),
      (v_raffle, 3, 'Teclado mecánico RGB + Mouse'),
      (v_raffle, 4, 'Audífonos Gamer 7.1'),
      (v_raffle, 5, 'Vale de compra S/ 300');
  ELSE
    UPDATE public.raffles SET ticket_price = 5 WHERE id = v_raffle;
  END IF;
END $$;

DO $$ DECLARE v_user_id uuid;
BEGIN
  SELECT id INTO v_user_id FROM auth.users WHERE lower(email) = lower('pcbox1508@gmail.com') LIMIT 1;
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'No se encontró pcbox1508@gmail.com. Crea el usuario en Supabase Auth y ejecuta nuevamente solo este bloque de asignación de rol.';
  ELSE
    INSERT INTO public.user_roles (user_id, role) VALUES (v_user_id, 'admin') ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
END $$;

COMMIT;
