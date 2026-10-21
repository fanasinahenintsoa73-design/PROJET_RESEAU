<?php
/**
 * Modeles de redaction institutionnels — Meteo Madagascar
 * ============================================================================
 * Mecanisme NATIF de Roundcube : $config['compose_responses_static'].
 *
 * Pourquoi ce fichier est separe de config.inc.php :
 *   config.inc.php contient les secrets (mot de passe MySQL, des_key) et n'est
 *   donc PAS versionne (voir .gitignore). Les modeles, eux, n'ont aucun secret
 *   : ils sont versionnes ici et injectes par le script 20-deploy-reponses.sh.
 *
 * Ce que fait ce mecanisme :
 *   - les modeles sont GLOBAUXS : visibles par tous les agents, des la
 *     premiere connexion, sans aucune ligne SQL par utilisateur ;
 *   - ils apparaissent dans la fenetre de redaction, section
 *     "Reponses enregistrees", au-dessus des modeles personnels ;
 *   - un agent ne peut pas les supprimer (ils ne sont pas dans SA table
 *     "responses") : c'est voulu, ce sont des modeles de l'institution.
 *
 * Structure d'une entree (voir program/include/rcmail.php, get_compose_response) :
 *   'name'  : libelle affiche dans la liste ;
 *   'text'  : corps en texte brut (is_html = false) ;
 *   'html'  : corps HTML (prioritaire sur 'text', is_html = true).
 *   L'un ou l'autre est obligatoire ; si les deux sont presents, 'html' gagne.
 *
 * Aucun placeholder n'est substitue par Roundcube : les crochets [ ] sont
 * meantes a etre remplaces a la main par l'agent.
 * ============================================================================
 */

$config['compose_responses_static'] = [

    // ---------------------------------------------------------------------
    // 1. Diffusion d'un bulletin meteorologique
    // ---------------------------------------------------------------------
    [
        'name' => 'Bulletin meteorologique - diffusion',
        'text' => <<<'TXT'
Madame, Monsieur,

Nous avons l'honneur de vous transmettre le bulletin meteorologique
du [date et heure] pour la zone [region / station].

resume du bulletin :
- Validite : [date et heure]
- Zone concernee : [region]
- Phenomenes significatifs : [resume en 2 ou 3 lignes]
- Validite : [duree]

Le bulletin complet est disponible en piece jointe.

Veuillez bien vouloir en assurer la diffusion aupres de vos equipes.

Veuillez agreer, Madame, Monsieur, l'expression de nos salutations
distinguées.

[Nom et fonction]
Direction Generale de la Meteorologie
Madagascar
TXT,
    ],

    // ---------------------------------------------------------------------
    // 2. Signalement d'un phenomenon par une station
    // ---------------------------------------------------------------------
    [
        'name' => 'Signalement d\'observation - station',
        'text' => <<<'TXT'
Bonjour,

Je signale l'observation suivante relevee a la station [nom de la station].

- Date et heure de l'observation : [jj/mm/aaaa hh:mm]
- Localisation : [region / commune]
- Intensite : [faible / moyenne / forte / tres forte]
- Type de phenomenon : [pluie / orage / grele / vent fort / foudre / inhibitions]
- cumul ou vitesse mesuree : [valeur et unite]
- Visibilite : [si pertinent]
- Degats ou consequences signales : [si pertinent]
- Photos ou radar en piece jointe : [oui / non]

La station reste operationnelle. [Preciser si necessaire]

Cordialement,
[Nom]
Station [nom]
TXT,
    ],

    // ---------------------------------------------------------------------
    // 3. Demande de releve ou de donnees a une station
    // ---------------------------------------------------------------------
    [
        'name' => 'Demande de releve / de donnees - station',
        'text' => <<<'TXT'
Bonjour,

Nous vous solicitedons de bien vouloir nous transmettre le releve
suivant pour la station [nom de la station].

- Donnees demandees : [precipitation / temperature / vent / humidite / pression / autre]
- Periode : [du jj/mm/aaaa au jj/mm/aaaa]
- Support de transmission : [rapport papier / fichier / transmission directe / autre]
- Date limite de retour : [jj/mm/aaaa]

Merci de nous signaler toute panne de transmission qui empecherait
ce retour.

Cordialement,
[Nom et fonction]
Direction Generale de la Meteorologie
TXT,
    ],

    // ---------------------------------------------------------------------
    // 4. Demande d'intervention technique
    // ---------------------------------------------------------------------
    [
        'name' => 'Demande d\'intervention technique',
        'text' => <<<'TXT'
Bonjour,

Je sollicite une intervention technique sur le materiel suivant.

- Station concernee : [nom de la station]
- Materiel en panne : [capteur / centrale / sonde / liaison / abri / autre]
- Symptome observe : [description factuelle]
- Debut de la panne : [jj/mm/aaaa hh:mm]
- Impact sur les observations : [aucun / releves non transmis / releves manuels]
- Photos du materiel : [oui / non]

Coordonnees du contact sur place : [nom, telephone]

Dans l'attente de votre intervention, les observations sont assurees
[par maniere / manuellement / autre].

Cordialement,
[Nom]
TXT,
    ],

    // ---------------------------------------------------------------------
    // 5. Accuse de reception standard
    // ---------------------------------------------------------------------
    [
        'name' => 'Accuse de reception',
        'text' => <<<'TXT'
Bonjour,

Nous accusons reception de votre message du [date et heure] relatif a [sujet].

[Phrase de suivi : actions engagees, echeance, ou simple confirmation.]

Nous restons a votre disposition.

Cordialement,
[Nom et fonction]
Direction Generale de la Meteorologie
TXT,
    ],

];
