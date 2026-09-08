-- Reinicio controlado del sorteo y sorteo de tres selecciones por premio.
-- Ejecutar una sola vez en el proyecto Supabase compartido.

BEGIN;

CREATE TABLE IF NOT EXISTS public.draw_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raffle_id uuid NOT NULL REFERENCES public.raffles(id) ON DELETE CASCADE,
  prize_id uuid NOT NULL REFERENCES public.prizes(id) ON DELETE CASCADE,
  attempt_number integer NOT NULL CHECK (attempt_number BETWEEN 1 AND 3),
  ticket_number integer NOT NULL,
  participant_name text NOT NULL,
  outcome text NOT NULL CHECK (outcome IN ('eliminado', 'ganador')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (prize_id, attempt_number),
  UNIQUE (raffle_id, ticket_number)
);

CREATE INDEX IF NOT EXISTS draw_attempts_prize_idx
  ON public.draw_attempts (prize_id, attempt_number);

ALTER TABLE public.draw_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.draw_attempts FROM anon;
GRANT SELECT ON public.draw_attempts TO authenticated;
GRANT ALL ON public.draw_attempts TO service_role;
DROP POLICY IF EXISTS "draw attempts admin read" ON public.draw_attempts;
CREATE POLICY "draw attempts admin read"
  ON public.draw_attempts FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

DROP FUNCTION IF EXISTS public.sortear_ganador(uuid);
CREATE OR REPLACE FUNCTION public.sortear_ganador(p_prize_id uuid)
RETURNS TABLE (
  ticket_number integer,
  winner_name text,
  attempt_number integer,
  outcome text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prize public.prizes%ROWTYPE;
  v_number integer;
  v_name text;
  v_attempt integer;
  v_outcome text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;
  SELECT p.* INTO v_prize FROM public.prizes AS p WHERE p.id = p_prize_id FOR UPDATE;
  IF v_prize.id IS NULL THEN RAISE EXCEPTION 'El premio no existe'; END IF;
  IF v_prize.winner_ticket_number IS NOT NULL THEN RAISE EXCEPTION 'Este premio ya tiene ganador'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_prize.raffle_id::text, 0));
  SELECT COALESCE(MAX(a.attempt_number), 0) + 1 INTO v_attempt FROM public.draw_attempts AS a WHERE a.prize_id = p_prize_id;
  IF v_attempt > 3 THEN RAISE EXCEPTION 'Este premio ya completó sus tres selecciones'; END IF;
  SELECT t.number, r.full_name INTO v_number, v_name
  FROM public.tickets AS t JOIN public.registrations AS r ON r.id = t.registration_id
  WHERE t.raffle_id = v_prize.raffle_id AND r.status = 'aprobado'
    AND NOT EXISTS (SELECT 1 FROM public.draw_attempts AS a WHERE a.raffle_id = v_prize.raffle_id AND a.ticket_number = t.number)
  ORDER BY random() LIMIT 1;
  IF v_number IS NULL THEN RAISE EXCEPTION 'No hay tickets aprobados disponibles'; END IF;
  v_outcome := CASE WHEN v_attempt = 3 THEN 'ganador' ELSE 'eliminado' END;
  INSERT INTO public.draw_attempts (raffle_id, prize_id, attempt_number, ticket_number, participant_name, outcome)
  VALUES (v_prize.raffle_id, p_prize_id, v_attempt, v_number, v_name, v_outcome);
  IF v_outcome = 'ganador' THEN
    UPDATE public.prizes AS p SET winner_ticket_number = v_number, winner_name = v_name WHERE p.id = p_prize_id;
  END IF;
  RETURN QUERY SELECT v_number, v_name, v_attempt, v_outcome;
END;
$$;

REVOKE ALL ON FUNCTION public.sortear_ganador(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sortear_ganador(uuid) TO authenticated, service_role;
UPDATE public.raffles SET status = 'inactivo' WHERE status = 'activo';
DELETE FROM public.raffles WHERE id = '0a33924c-741b-4d4c-bd67-90fed891ce35'::uuid OR title = '1° Gran Sorteo del Shucuy Regalon';
INSERT INTO public.raffles (title, description, details, image_url, ticket_price, status, draw_date)
SELECT 'Sorteo PC BOX - Próximamente', 'Nuevo sorteo PC BOX. Los premios serán publicados próximamente.', 'Sorteo en preparación. Cada ticket tendrá un valor de S/ 5 y será validado mediante comprobante de Yape.', 'assets/logo-pcbox-nuevo.png', 5, 'activo', '2026-10-08 23:59:59-05:00'
WHERE NOT EXISTS (SELECT 1 FROM public.raffles WHERE title = 'Sorteo PC BOX - Próximamente');

COMMIT;
