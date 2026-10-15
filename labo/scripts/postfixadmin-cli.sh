#!/bin/bash
# =============================================================================
# postfixadmin-cli - lanceur pour le depot /opt/postfixadmin
# Le script officiel (/opt/postfixadmin/scripts/postfixadmin-cli) resout sa
# propre racine via readlink ; on l'appelle directement pour eviter toute
# dependance a l'emplacement du symlink.
# =============================================================================
exec php -q /opt/postfixadmin/scripts/postfixadmin-cli.php "$@"