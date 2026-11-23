// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 jrdoublet
/* PUB-05b : file de priorite minimale sur une liste native.
 *
 * Ecrite pour OpexAI a partir de la seule API NoAI (AIList). Les elements sont des
 * entiers (des tuiles pour l'A* routier) ; la priorite est un entier, la plus petite
 * sort en premier. Le tri, l'insertion et le retrait sont faits en C++ par AIList :
 * une operation coute quelques opcodes Squirrel, quelle que soit la taille de la file,
 * la ou un tas ecrit en Squirrel en paie plusieurs dizaines par niveau.
 *
 * Contrat (celui dont road1y_astar.nut a besoin) :
 * - Insert(item, priority) : un element deja present garde la plus petite des deux
 *   priorites (diminution de cle). L'A* appelant ignore de toute facon un element deja
 *   ferme ; garder un seul exemplaire evite seulement les retraits inutiles.
 * - Pop() : retire et rend l'element de plus petite priorite, null si la file est vide.
 *   A priorite egale, AIList rend le plus petit identifiant.
 * - Peek(), Count(), IsEmpty().
 * Aucun etat n'est sauvegarde : AIList n'est pas serialisable, la file vit le temps
 * d'une recherche. */

class OpexMinQueue
{
  _list = null;

  constructor()
  {
    this._list = AIList();
    this._list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
  }

  function Insert(item, priority)
  {
    local list = this._list;
    if (!list.HasItem(item)) {
      list.AddItem(item, priority);
    } else if (priority < list.GetValue(item)) {
      list.SetValue(item, priority);
    }
  }

  function Pop()
  {
    local list = this._list;
    if (list.IsEmpty()) return null;
    local item = list.Begin();
    list.RemoveItem(item);
    return item;
  }

  function Peek()
  {
    if (this._list.IsEmpty()) return null;
    return this._list.Begin();
  }

  function Count()
  {
    return this._list.Count();
  }

  function IsEmpty()
  {
    return this._list.IsEmpty();
  }
}
