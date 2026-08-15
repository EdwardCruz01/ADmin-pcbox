# PC BOX Admin Dashboard

Dashboard independiente para administrar la web pública de sorteos PC BOX.

## Uso

1. En Supabase Auth crea el usuario `pcbox1508@gmail.com` con el nombre visible `adminPcbox` y la contraseña definida por el propietario.
2. Si partes de una base nueva, ejecuta una sola vez el archivo `supabase/SETUP-ALL.sql` en SQL Editor. Crea tablas, políticas, funciones, el sorteo inicial a S/ 5.00 y asigna el rol `admin`.
3. Si tu base ya tiene las tablas, ejecuta `supabase/production-setup.sql` y la migración `supabase/migrations/20260815100000_admin_dashboard_security.sql`.
4. Sirve la carpeta `admin/` con Live Server, cualquier servidor estático o Vite.
5. Inicia sesión con `pcbox1508@gmail.com`.

El proyecto conectado es `https://eskfubdoqbkrdxvlvlti.supabase.co` y la web usa su publishable key. La publishable key puede estar en el frontend; nunca agregues una `service_role` o `sb_secret` a este paquete.

Asignación manual del rol, si la necesitas:

```sql
insert into public.user_roles (user_id, role)
values ('UUID_DEL_USUARIO_AUTH', 'admin')
on conflict (user_id, role) do nothing;
```

Las funciones de aprobación, eliminación y sorteo validan `public.has_role(auth.uid(), 'admin')` en PostgreSQL.
