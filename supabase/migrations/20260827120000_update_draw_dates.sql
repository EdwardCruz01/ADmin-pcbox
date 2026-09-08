-- Fechas definitivas de las dos tarjetas del sorteo.
BEGIN;
UPDATE public.raffles SET draw_date = '2026-08-27 22:00:00-05:00', status = 'activo' WHERE title = 'Sorteo PC BOX - Próximamente';
UPDATE public.raffles SET draw_date = '2026-10-08 23:59:59-05:00', status = 'inactivo' WHERE title = '1° Gran Sorteo del Shucuy Regalon';
COMMIT;
