-- PC BOX | Configuración de producción
-- Ejecutar en Supabase SQL Editor DESPUÉS de aplicar las migraciones de esta carpeta
-- en orden alfabético. Antes de ejecutar este archivo, crea en Supabase Auth:
--   correo: pcbox1508@gmail.com
--   nombre visible: adminPcbox
--   contraseña: la definida por el propietario (nunca se guarda en este archivo)

BEGIN;

-- Precio oficial del sorteo y precio por defecto para nuevos sorteos.
ALTER TABLE public.raffles ALTER COLUMN ticket_price SET DEFAULT 5;
UPDATE public.raffles SET ticket_price = 5 WHERE status = 'activo';

-- Comprobantes privados, máximo 10 MB y solo formatos permitidos.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'comprobantes',
  'comprobantes',
  false,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "comprobantes admin read" ON storage.objects;
CREATE POLICY "comprobantes admin read"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'comprobantes' AND public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "comprobantes admin delete" ON storage.objects;
CREATE POLICY "comprobantes admin delete"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'comprobantes' AND public.has_role(auth.uid(), 'admin'));

-- El dashboard solo puede invocar estas operaciones con una sesión admin.
GRANT EXECUTE ON FUNCTION public.aprobar_inscripcion(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rechazar_inscripcion(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.eliminar_inscripcion(p_registration_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  DELETE FROM public.registrations WHERE id = p_registration_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sortear_ganador(p_prize_id uuid)
RETURNS TABLE (ticket_number int, winner_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prize public.prizes%ROWTYPE;
  v_number int;
  v_name text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  SELECT * INTO v_prize FROM public.prizes WHERE id = p_prize_id FOR UPDATE;
  IF v_prize.id IS NULL THEN RAISE EXCEPTION 'El premio no existe'; END IF;
  IF v_prize.winner_ticket_number IS NOT NULL THEN RAISE EXCEPTION 'Este premio ya tiene ganador'; END IF;

  SELECT t.number, r.full_name INTO v_number, v_name
  FROM public.tickets t
  JOIN public.registrations r ON r.id = t.registration_id
  WHERE t.raffle_id = v_prize.raffle_id
    AND r.status = 'aprobado'
    AND NOT EXISTS (
      SELECT 1 FROM public.prizes p
      WHERE p.raffle_id = v_prize.raffle_id
        AND p.winner_ticket_number = t.number
    )
  ORDER BY random()
  LIMIT 1;

  IF v_number IS NULL THEN RAISE EXCEPTION 'No hay tickets aprobados disponibles'; END IF;

  UPDATE public.prizes
  SET winner_ticket_number = v_number, winner_name = v_name
  WHERE id = p_prize_id;

  RETURN QUERY SELECT v_number, v_name;
END;
$$;

REVOKE ALL ON FUNCTION public.eliminar_inscripcion(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sortear_ganador(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.eliminar_inscripcion(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sortear_ganador(uuid) TO authenticated;

-- Asigna el rol admin al usuario Auth indicado.
DO $$
DECLARE
  v_user_id uuid;
BEGIN
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE lower(email) = lower('pcbox1508@gmail.com')
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE NOTICE 'No se encontró pcbox1508@gmail.com. Créalo en Authentication > Users y ejecuta nuevamente este bloque de asignación de rol.';
  ELSE
    INSERT INTO public.user_roles (user_id, role)
    VALUES (v_user_id, 'admin')
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
END;
$$;

COMMIT;
