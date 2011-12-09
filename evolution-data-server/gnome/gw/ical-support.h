/* guile-gnome
 * Copyright (C) 2004 Free Software Foundation, Inc.
 *
 * ical-support.c: Support routines for the evolution-data-server wrapper
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

#include <libical/ical.h>
#include "guile-gnome-gobject.h"

GType icaltimetype_get_gtype (void);
struct icaltimetype* scm_date_to_icaltimetype (SCM date);
SCM scm_icaltimetype_to_date (struct icaltimetype *t);

SCM scm_c_module_ref (SCM module, const char *sym);
