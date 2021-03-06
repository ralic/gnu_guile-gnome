/* guile-gnome
 * Copyright (C) 2006 Andy Wingo <wingo at pobox dot com>
 *
 * gc.h: A sweep-safe replacement for scm_gc_protect_object
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

#ifndef __GUILE_GNOME_GOBJECT_GC_H__
#define __GUILE_GNOME_GOBJECT_GC_H__


#include <glib.h>
#include <libguile.h>


G_BEGIN_DECLS


gpointer scm_glib_gc_protect_object (SCM obj);
void scm_glib_gc_unprotect_object (gpointer key);


void scm_init_gnome_gobject_gc (void);


G_END_DECLS


#endif /* __GUILE_GNOME_GOBJECT_GC_H__ */
