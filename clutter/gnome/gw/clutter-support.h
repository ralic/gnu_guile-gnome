/* guile-gnome
 * Copyright (C) 2008 Free Software Foundation, Inc.
 *
 * clutter-support.h:
 *
 * This program is free software; you can redistribute it and/or    
 * modify it under the terms of the GNU General Public License as   
 * published by the Free Software Foundation; either version 2 of   
 * the License, or (at your option) any later version.              
 *                                                                  
 * This program is distributed in the hope that it will be useful,  
 * but WITHOUT ANY WARRANTY; without even the implied warranty of   
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the    
 * GNU General Public License for more details.                     
 *                                                                  
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, contact:
 *
 * Free Software Foundation           Voice:  +1-617-542-5942
 * 59 Temple Place - Suite 330        Fax:    +1-617-542-2652
 * Boston, MA  02111-1307,  USA       gnu@gnu.org
 */

#include <clutter/clutter.h>
#include <libguile.h>
#include "guile-gnome-gobject.h"

SCM scm_clutter_knot_to_scm (ClutterKnot *k);
ClutterKnot* scm_scm_to_clutter_knot (SCM scm);

SCM scm_clutter_path_node_to_scm (ClutterPathNode *k);
ClutterPathNode* scm_scm_to_clutter_path_node (SCM scm);

SCM scm_clutter_color_to_scm (ClutterColor *c);
ClutterColor* scm_scm_to_clutter_color (SCM scm);

SCM scm_clutter_actor_box_to_scm (ClutterActorBox *a);
ClutterActorBox* scm_scm_to_clutter_actor_box (SCM scm);

SCM scm_clutter_geometry_to_scm (ClutterGeometry *g);
ClutterGeometry* scm_scm_to_clutter_geometry (SCM scm);

SCM scm_clutter_vertex_to_scm (ClutterVertex *x);
ClutterVertex* scm_scm_to_clutter_vertex (SCM scm);

SCM scm_clutter_perspective_to_scm (ClutterPerspective *x);
ClutterPerspective* scm_scm_to_clutter_perspective (SCM scm);
SCM wrap_clutter_stage_get_perspective (ClutterStage *stage);

SCM scm_clutter_fog_to_scm (ClutterFog *x);
ClutterFog* scm_scm_to_clutter_fog (SCM scm);
SCM wrap_clutter_stage_get_fog (ClutterStage *stage);

SCM _wrap_clutter_color_from_string (const char *name);

ClutterUnits* wrap_clutter_units_from_pixels (gint px);
ClutterUnits* wrap_clutter_units_from_em (gfloat em);
ClutterUnits* wrap_clutter_units_from_em_for_font (const gchar *font_name, gfloat em);
ClutterUnits* wrap_clutter_units_from_mm (gfloat mm);
ClutterUnits* wrap_clutter_units_from_pt (gfloat pt);
ClutterUnits* wrap_clutter_units_from_string (const gchar *str);