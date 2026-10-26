-- Keep existing accounts and historical inspection records; remove only this role.
-- An account losing its only active permission keeps ordinary user access, never ADMIN.
INSERT INTO camerahub.user_roles(user_id, role_code)
SELECT DISTINCT retired.user_id, 'BUYER'
FROM camerahub.user_roles retired
WHERE retired.role_code = 'INSPECTOR'
  AND NOT EXISTS (
    SELECT 1 FROM camerahub.user_roles existing_role
    WHERE existing_role.user_id = retired.user_id
      AND existing_role.role_code IN ('BUYER', 'ADMIN')
  )
ON CONFLICT (user_id, role_code) DO NOTHING;

DELETE FROM camerahub.user_roles WHERE role_code = 'INSPECTOR';
DELETE FROM camerahub.roles WHERE code = 'INSPECTOR';

ALTER TABLE camerahub.roles DROP CONSTRAINT IF EXISTS roles_code_check;
ALTER TABLE camerahub.roles ADD CONSTRAINT roles_code_check
  CHECK (code IN ('BUYER', 'SELLER', 'ADMIN'));
