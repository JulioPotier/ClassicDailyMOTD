# Addon behavior for multiple officers
_Exported on 5/13/2026 at 14:08:22 GMT+2 from Cursor (3.3.30)_

---

**User**

Le projet est un addon e World of warcraft classic hardcore v1.15.8 rédigé en anglais pour les textes et labels. voici les fichiers,@RandomDailyMOTD.lua @RandomDailyMOTD.toc Cet addon modifie tous les jours le MOTD de la guilde en cours par une valeur aléatoire.
Question: que se passe-t-il si 2 officiers de cette mlême guilde utilisent cet addon ? J'ai l'impression que cela va la changer pour chaque officier et donc 2 fois, tu confirmes ?

---

**Cursor**

Examen du code de l'addon pour confirmer le comportement lorsque plusieurs officiers l'utilisent.



Oui, ton intuition est bonne, avec une nuance sur ce qui est « deux fois ».

## Ce que fait vraiment l’addon

À la connexion (`PLAYER_LOGIN`), après 5 secondes, `SetDailyMOTD()` s’exécute. Il ne met à jour le MOTD que si :

1. tu es dans une guilde et tu as le droit de modifier le MOTD (`CanEditMOTD()`), et  
2. **`RDGM_Saved.lastDate` n’est pas déjà la date du jour** sur **ce** client.

```13:36:c:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\RandomDailyMOTD\RandomDailyMOTD.lua
local function SetDailyMOTD()
    if not IsInGuild() or not CanEditMOTD() then
        return
    end

    local today = date("%Y-%m-%d")

    if RDGM_Saved.lastDate == today then
        return
    end
    -- ...
    GuildSetMOTD(newMOTD)
    RDGM_Saved.lastDate = today
```

`RDGM_Saved` est une **variable sauvegardée locale** au compte WoW (fichier côté client), pas partagée entre les joueurs. La date « déjà fait aujourd’hui » ne concerne que **cette installation / ce compte**.

## Deux officiers avec l’addon

- **Officier A** : si sa dernière date enregistrée n’est pas aujourd’hui, l’addon tire au sort et appelle `GuildSetMOTD` → le MOTD de la guilde change (une fois pour cette session côté A).
- **Officier B** : son propre `RDGM_Saved` est indépendant. S’il n’a pas encore `lastDate == aujourd’hui` chez lui, **son** addon fera **encore** un tirage et un `GuildSetMOTD` → le MOTD peut changer **une deuxième fois**, souvent avec un autre message aléatoire.

Donc ce n’est pas « deux fois pour chaque officier » au sens strict (chaque client ne met à jour qu’**une** fois par jour **par compte** après reconnexion, grâce à `lastDate`), mais **jusqu’à une mise à jour par jour et par joueur qui a l’addon et le droit MOTD** : en pratique, plusieurs officiers peuvent enchaîner plusieurs changements le même jour sur la **même** guilde.

## Résumé

| Situation | Effet sur le MOTD de guilde |
|-----------|-----------------------------|
| Même officier, plusieurs connexions le même jour | En général **non** : `lastDate` bloque. |
| Plusieurs officiers, chacun avec l’addon | **Oui** : chacun peut appliquer « son » tirage du jour ; le dernier `GuildSetMOTD` gagne. |

Il n’y a pas de synchronisation entre clients : l’addon ne sait pas qu’un autre officier a déjà changé le MOTD aujourd’hui. Pour n’avoir qu’un seul tirage par guilde et par jour, il faudrait une logique hors-addon (un seul officier l’utilise, ou une règle de guilde) ou une implémentation différente (par ex. stockage partagé impossible en pur client sans serveur — en jeu il n’y a pas d’API simple pour « un seul tirage par guilde » sans convention ou addon côté un seul compte).

