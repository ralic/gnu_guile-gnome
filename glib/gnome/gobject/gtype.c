/* -*- Mode: C; c-basic-offset: 4 -*- */
/* guile-gnome
 * Copyright (C) 2001 Martin Baulig <martin@gnome.org>
 *
 * gtype.c: Base support for the GLib type system
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


#include <stdio.h>
#include <string.h>
#include "guile-support.h"
#include "gc.h"
#include "gutil.h"
#include "gtype.h"
#include "private.h"



SCM_GLOBAL_SYMBOL  (scm_sym_gtype,		"gtype");
SCM_GLOBAL_SYMBOL  (scm_sym_gtype_instance,	"gtype-instance");

SCM scm_class_gtype_class;
SCM scm_class_gtype_instance;
SCM scm_sys_gtype_to_class;

/* bummer */
extern SCM scm_class_gvalue;



SCM_SYMBOL  (sym_gruntime_error,"gruntime-error");
SCM_SYMBOL  (sym_name,		"name");

SCM_KEYWORD (k_name,		"name");
SCM_KEYWORD (k_class,		"class");
SCM_KEYWORD (k_metaclass,	"metaclass");
SCM_KEYWORD (k_gtype_name,	"gtype-name");


static SCM _make_class;
static SCM _class_redefinition;
static SCM _allocate_instance;
static SCM _initialize;

static SCM _gtype_name_to_scheme_name;
static SCM _gtype_name_to_class_name;

static GQuark quark_class = 0;
static GQuark quark_type = 0;
static GQuark quark_guile_gtype_class = 0;
static GQuark guile_gobject_quark_wrapper;



/* #define DEBUG_PRINT */

#ifdef DEBUG_PRINT
#define DEBUG_ALLOC(str, args...) g_print ("I: " str "\n", ##args)
#else
#define DEBUG_ALLOC(str, args...)
#endif



static void scm_gtype_instance_unbind (scm_t_bits *slots);

/* would be nice to assume everything uses InitiallyUnowned, but that's not the
 * case... */
typedef struct {
    GType type;
    void (* sinkfunc)(gpointer instance);
} SinkFunc;

static GSList *gtype_instance_funcs = NULL;
static GArray *sink_funcs = NULL;



/**********************************************************************
 * GTypeClass
 **********************************************************************/

SCM
scm_c_gtype_lookup_class (GType gtype)
{
    SCM class;

    class = g_type_get_qdata (gtype, quark_class);

    return class ? class : SCM_BOOL_F;
}

static SCM
scm_c_gtype_get_direct_supers (GType type)
{
    GType parent = g_type_parent (type);
    SCM ret = SCM_EOL;
    
    if (!parent) {
        if (G_TYPE_IS_INSTANTIATABLE (type))
            ret = scm_cons (scm_class_gtype_instance, ret);
        else
            ret = scm_cons (scm_class_gvalue, ret);
    } else {
        SCM direct_super, cpl;
        GType *interfaces;
        guint n_interfaces, i;
        
        direct_super = scm_c_gtype_to_class (parent);
        cpl = scm_class_precedence_list (direct_super);
        ret = scm_cons (direct_super, ret);

        interfaces = g_type_interfaces (type, &n_interfaces);
        if (interfaces) {
            for (i=0; i<n_interfaces; i++) {
                SCM iclass = scm_c_gtype_to_class (interfaces[i]);
                if (scm_is_false (scm_c_memq (iclass, cpl)))
                    ret = scm_cons (iclass, ret);
            }
            g_free (interfaces);
        }
    }
    
    return ret;
}

SCM
scm_c_gtype_to_class (GType gtype)
{
    SCM ret, supers, gtype_name, name;
    
    ret = scm_c_gtype_lookup_class (gtype);
    if (SCM_NFALSEP (ret))
        return ret;
    
    supers = scm_c_gtype_get_direct_supers (gtype);
    gtype_name = scm_from_locale_string (g_type_name (gtype));
    name = scm_call_1 (_gtype_name_to_class_name, gtype_name);
    
    ret = scm_apply_0 (_make_class,
                       scm_list_n (supers, SCM_EOL,
                                   k_gtype_name, gtype_name,
                                   k_name, name, SCM_UNDEFINED));
    
    /* assert (scm_c_gtype_lookup_class (gtype) == ret); */

    return ret;
}

SCM_DEFINE_STATIC (_gtype_to_class, "%gtype->class", 1, 0, 0,
                   (SCM ulong))
{
    return scm_c_gtype_to_class (scm_to_ulong (ulong));
}

SCM_DEFINE (scm_gtype_name_to_class, "gtype-name->class", 1, 0, 0,
            (SCM name),
            "Return the @code{<gtype-class>} associated with the GType, @var{name}.")
#define FUNC_NAME s_scm_gtype_name_to_class
{
    GType type;
    gchar *chars;

    SCM_VALIDATE_STRING (1, name);

    scm_dynwind_begin (0);
    chars = scm_to_locale_string (name);
    scm_dynwind_free (chars);    

    type = g_type_from_name (chars);
    if (!type)
        scm_c_gruntime_error (FUNC_NAME,
                              "No GType registered with name ~A",
                              SCM_LIST1 (name));

    scm_dynwind_end ();

    return scm_c_gtype_to_class (type);
}
#undef FUNC_NAME

SCM_DEFINE_STATIC (scm_sys_gtype_class_bind, "%gtype-class-bind", 2, 0, 0,
                   (SCM class, SCM type_name))
#define FUNC_NAME s_scm_sys_gtype_class_bind
{
    GType gtype;
    char *c_type_name;

    SCM_VALIDATE_GTYPE_CLASS (1, class);
    SCM_VALIDATE_STRING (2, type_name);

    if (scm_c_gtype_class_to_gtype (class))
        scm_c_gruntime_error (FUNC_NAME,
                              "Class ~A already has a GType",
                              SCM_LIST1 (type_name));

    scm_dynwind_begin (0);
    c_type_name = scm_to_locale_string (type_name);
    scm_dynwind_free (c_type_name);
    
    gtype = g_type_from_name (c_type_name);
    if (!gtype)
        scm_c_gruntime_error (FUNC_NAME,
                              "No GType registered with name ~A",
                              SCM_LIST1 (type_name));


    if (SCM_NFALSEP (scm_c_gtype_lookup_class (gtype)))
        scm_c_gruntime_error (FUNC_NAME,
                              "~A already has a GOOPS class, use gtype-name->class",
                              SCM_LIST1 (type_name));
    
    g_type_set_qdata (gtype, quark_class, scm_permanent_object (class));
    scm_slot_set_x (class, scm_sym_gtype, scm_from_ulong (gtype));
        
    scm_dynwind_end ();

    return SCM_UNSPECIFIED;
}
#undef FUNC_NAME

#if SCM_MAJOR_VERSION == 1 && SCM_MINOR_VERSION < 9
# define scm_vtable_index_instance_finalize scm_struct_i_free
static size_t
scm_gtype_instance_struct_free (scm_t_bits * vtable, scm_t_bits * data)
{
    scm_gtype_instance_unbind (data);
    scm_struct_free_light (vtable, data);
    return 0;
}
#else
static void
scm_gtype_instance_struct_free (SCM object)
{
    scm_gtype_instance_unbind (SCM_STRUCT_DATA (object));
}
#endif

SCM_DEFINE_STATIC (scm_sys_gtype_class_inherit_magic, "%gtype-class-inherit-magic", 1, 0, 0,
                   (SCM class))
#define FUNC_NAME s_scm_sys_gtype_class_inherit_magic
{
    GType gtype;
    scm_t_bits *slots;

    SCM_VALIDATE_GTYPE_CLASS_COPY (1, class, gtype);

    slots = SCM_STRUCT_DATA (class);
    /* inherit class free function */
    if (g_type_parent (gtype)) {
        SCM parent = scm_c_gtype_to_class (g_type_parent (gtype));
        slots[scm_vtable_index_instance_finalize] =
            SCM_STRUCT_DATA (parent)[scm_vtable_index_instance_finalize];
    } else if (G_TYPE_IS_INSTANTIATABLE (gtype)) {
        slots[scm_vtable_index_instance_finalize] =
            (scm_t_bits)scm_gtype_instance_struct_free;
#if SCM_MAJOR_VERSION == 1 && SCM_MINOR_VERSION < 9
    } else if (slots[scm_vtable_index_instance_finalize] == (scm_t_bits)scm_struct_free_light) {
        SCM parent = scm_cadr (scm_class_precedence_list (class));
        slots[scm_vtable_index_instance_finalize] =
            SCM_STRUCT_DATA (parent)[scm_vtable_index_instance_finalize];
    } else {
        scm_c_gruntime_error (FUNC_NAME, "No free function for SCM class %s!",
                              SCM_LIST1 (class));
#else
    } else {
        SCM parent = scm_cadr (scm_class_precedence_list (class));
        /* is this right? layout might not be the same. */
        slots[scm_vtable_index_instance_finalize] =
            SCM_STRUCT_DATA (parent)[scm_vtable_index_instance_finalize];
#endif
    }

    return SCM_UNSPECIFIED;
}
#undef FUNC_NAME

GType
scm_c_gtype_class_to_gtype (SCM klass)
#define FUNC_NAME "%gtype-class->gtype"
{
    SCM_VALIDATE_GTYPE_CLASS (1, klass);
    
    return scm_to_ulong (scm_slot_ref (klass, scm_sym_gtype));
}
#undef FUNC_NAME

gboolean
scm_c_gtype_class_is_a_p (SCM instance, GType gtype)
{
    return g_type_is_a (scm_c_gtype_class_to_gtype (instance), gtype);
}



/**********************************************************************
 * GTypeInstance
 **********************************************************************/

static scm_t_gtype_instance_funcs*
get_gtype_instance_instance_funcs (GType type)
{
    GSList *l;
    GType fundamental;
    fundamental = G_TYPE_FUNDAMENTAL (type);
    for (l = gtype_instance_funcs; l; l = l->next) {
        scm_t_gtype_instance_funcs *ret = l->data;
        if (fundamental == ret->type)
            return ret;
    }
    return NULL;
}

void
scm_register_gtype_instance_funcs (const scm_t_gtype_instance_funcs *funcs)
{
    gtype_instance_funcs = g_slist_append (gtype_instance_funcs,
                                           (gpointer)funcs);
}

gpointer
scm_c_gtype_instance_ref (gpointer instance)
{
    scm_t_gtype_instance_funcs *funcs;
    funcs = get_gtype_instance_instance_funcs (G_TYPE_FROM_INSTANCE (instance));
    if (funcs && funcs->ref) {
        funcs->ref (instance);
#ifdef DEBUG_PRINT
        {
            /* ugly. */
            glong refcount;
            if (G_IS_OBJECT (instance))
                refcount = ((GObject*)instance)->ref_count;
            else if (G_IS_PARAM_SPEC (instance))
                refcount = ((GParamSpec*)instance)->ref_count;
            else
                refcount = -99;
            DEBUG_ALLOC ("reffed instance (%p) of type %s, ->%ld",
                         instance, g_type_name (G_TYPE_FROM_INSTANCE (instance)),
                         refcount);
        }
#endif        
    }

    return instance;
}

void
scm_c_gtype_instance_unref (gpointer instance)
{
    scm_t_gtype_instance_funcs *funcs;
    funcs = get_gtype_instance_instance_funcs (G_TYPE_FROM_INSTANCE (instance));
#ifdef DEBUG_PRINT
    {
        /* ugly. */
        glong refcount;
        if (G_IS_OBJECT (instance))
            refcount = ((GObject*)instance)->ref_count;
        else if (G_IS_PARAM_SPEC (instance))
            refcount = ((GParamSpec*)instance)->ref_count;
        else
            refcount = -99;
        DEBUG_ALLOC ("unreffing instance (%p) of type %s, %ld->",
                     instance, g_type_name (G_TYPE_FROM_INSTANCE (instance)),
                     refcount);
    }
#endif        
    if (funcs && funcs->unref)
        funcs->unref (instance);
    /* else */
    /*     g_type_free_instance (instance); */
}

static SCM
scm_c_gtype_instance_get_cached (gpointer instance)
{
    SCM ret;
    scm_t_gtype_instance_funcs *funcs;
    funcs = get_gtype_instance_instance_funcs (G_TYPE_FROM_INSTANCE (instance));
    if (funcs && funcs->get_qdata) {
        gpointer data = funcs->get_qdata ((GObject*)instance,
                                          guile_gobject_quark_wrapper);
        if (data) {
            ret = GPOINTER_TO_SCM (data);
#if SCM_MAJOR_VERSION == 1 && SCM_MINOR_VERSION < 9
            scm_gc_mark (ret);
#endif
            return ret;
        }
    }
    return SCM_BOOL_F;
}

static void
scm_c_gtype_instance_set_cached (gpointer instance, SCM scm)
{
    scm_t_gtype_instance_funcs *funcs;
    funcs = get_gtype_instance_instance_funcs (G_TYPE_FROM_INSTANCE (instance));
    if (funcs && funcs->set_qdata)
        funcs->set_qdata ((GObject*)instance,
                          guile_gobject_quark_wrapper,
                          scm == SCM_BOOL_F ? NULL : SCM_TO_GPOINTER (scm));
}

static gpointer
scm_c_gtype_instance_construct (SCM object, SCM initargs)
{
    GType type;
    scm_t_gtype_instance_funcs *funcs;
    type = scm_c_gtype_class_to_gtype (scm_class_of (object));
    funcs = get_gtype_instance_instance_funcs (type);
    if (funcs && funcs->construct)
        return funcs->construct (object, initargs);
    else
        scm_c_gruntime_error ("%gtype-instance-construct",
                              "Don't know how to construct instances of class ~A",
                              SCM_LIST1 (scm_c_gtype_to_class (type)));
    return NULL;
}

static void
scm_c_gtype_instance_initialize_scm (SCM object, gpointer instance)
{
    GType type;
    scm_t_gtype_instance_funcs *funcs;
    type = scm_c_gtype_class_to_gtype (scm_class_of (object));
    funcs = get_gtype_instance_instance_funcs (type);
    if (funcs && funcs->initialize_scm)
        funcs->initialize_scm (object, instance);
}

/* idea, code, and comments stolen from pygtk -- thanks, James :-) */
static inline void
sink_type_instance (gpointer instance)
{
    if (sink_funcs) {
	gint i;

	for (i = 0; i < sink_funcs->len; i++) {
	    if (g_type_is_a (G_TYPE_FROM_INSTANCE (instance),
                             g_array_index (sink_funcs, SinkFunc, i).type)) {
		g_array_index (sink_funcs, SinkFunc, i).sinkfunc (instance);

#ifdef DEBUG_PRINT
                if (G_IS_OBJECT (instance)) {
                    DEBUG_ALLOC ("sunk gobject (%p) of type %s, ->%u",
                                 instance, g_type_name (G_TYPE_FROM_INSTANCE (instance)),
                                 ((GObject*)instance)->ref_count);
                }
#endif
		break;
	    }
	}
    }
}

/**
 * As Guile handles memory management for us, the "floating reference" code in
 * GTK actually causes memory leaks for objects that are never parented. For
 * this reason, guile-gobject removes the floating references on objects on
 * construction.
 *
 * The sinkfunc should be able to remove the floating reference on
 * instances of the given type, or any subclasses.
 */
void
scm_register_gtype_instance_sinkfunc (GType type, void (*sinkfunc) (gpointer))
{
    SinkFunc sf;

    if (!sink_funcs)
	sink_funcs = g_array_new (FALSE, FALSE, sizeof(SinkFunc));

    sf.type = type;
    sf.sinkfunc = sinkfunc;
    g_array_append_val (sink_funcs, sf);
}

static void
scm_gtype_instance_unbind (scm_t_bits *slots)
{
    gpointer instance = (gpointer)slots[0];
    
    if (instance && instance != SCM_UNBOUND) {
        DEBUG_ALLOC ("unbind c object 0x%p", instance);

        slots[0] = 0;
        scm_c_gtype_instance_set_cached (instance, SCM_BOOL_F);
        scm_c_gtype_instance_unref (instance);
    }
}

void
scm_c_gtype_instance_bind_to_object (gpointer ginstance, SCM object)
{
    scm_t_bits *slots = SCM_STRUCT_DATA (object);
    
    scm_c_gtype_instance_ref (ginstance);
    /* sink the floating ref, if any */
    sink_type_instance (ginstance);
    slots[0] = (scm_t_bits)ginstance;

    /* Cache the return value, so that if a callback or another function returns
     * this ginstance while the ginstance is visible elsewhere, the same wrapper
     * will be used. Released in unbind(). */
    scm_c_gtype_instance_set_cached (ginstance, object);

    DEBUG_ALLOC ("bound SCM 0x%p to 0x%p", (void*)object, ginstance);
}

SCM_DEFINE_STATIC (scm_sys_gtype_instance_construct, "%gtype-instance-construct", 2, 0, 0,
                   (SCM instance, SCM initargs))
{
    gpointer ginstance = (gpointer)SCM_STRUCT_DATA (instance)[0];

    if (ginstance && ginstance != (gpointer)SCM_UNBOUND) {
        scm_c_gtype_instance_initialize_scm (instance, ginstance);
    } else {
        gpointer new_ginstance;
        new_ginstance = scm_c_gtype_instance_construct (instance, initargs);
        ginstance = (gpointer)SCM_STRUCT_DATA (instance)[0];
        
        /* it's possible the construct function bound the object already, as is
         * the case for scheme-defined gobjects */
        if (new_ginstance != ginstance)
            scm_c_gtype_instance_bind_to_object (new_ginstance, instance);

        scm_c_gtype_instance_unref (new_ginstance);
    }
        
    return SCM_UNSPECIFIED;
}

SCM_DEFINE (scm_gtype_instance_destroy_x, "gtype-instance-destroy!", 1, 0, 0,
	    (SCM instance),
	    "Release all references that the Scheme wrapper @var{instance} "
            "has on the underlying C value, and release pointers associated "
            "with the C value that point back to Scheme.\n\n"
            "Normally, you don't need to call this function, because garbage "
            "collection will take care of resource management. "
            "However some @code{<gtype-class>} instances have semantics that "
            "require this function. The canonical example is that when a "
            "@code{<gtk-object>} emits the @code{destroy} signal, all "
            "code should drop their references to the object. This is, "
            "of course, handled internally in the @code{(gnome gtk)} "
            "module.")
#define FUNC_NAME s_scm_gtype_instance_destroy_x
{
    SCM_VALIDATE_GTYPE_INSTANCE (1, instance);

    scm_gtype_instance_unbind (SCM_STRUCT_DATA (instance));

    return SCM_UNSPECIFIED;
}
#undef FUNC_NAME

gpointer
scm_c_scm_to_gtype_instance (SCM instance)
{
    SCM ulong;
    gpointer ginstance;

    if (!SCM_IS_A_P (instance, scm_class_gtype_instance))
	return NULL;

    /* FIXME: the following code should work, but slot-ref on 'u' slots was
       busted until guile 1.8.5 
       ulong = scm_slot_ref (instance, scm_sym_gtype_instance);
    */
    ulong = scm_from_ulong (SCM_STRUCT_DATA (instance)[0]);

    if (ulong == SCM_UNBOUND)
        scm_c_gruntime_error ("%scm->gtype-instance",
                              "Object ~A is uninitialized.",
                              SCM_LIST1 (instance));

    ginstance = (gpointer)scm_to_ulong (ulong);
    
    if (!ginstance)
        scm_c_gruntime_error ("%scm->gtype-instance",
                              "Object ~A has been destroyed.",
                              SCM_LIST1 (instance));

    return ginstance;
}

gboolean
scm_c_gtype_instance_is_a_p (SCM instance, GType gtype)
{
    return scm_c_scm_to_gtype_instance_typed (instance, gtype) != NULL;
}

gpointer
scm_c_scm_to_gtype_instance_typed (SCM instance, GType gtype)
{
    gpointer ginstance = scm_c_scm_to_gtype_instance (instance);

    if (!G_TYPE_CHECK_INSTANCE_TYPE (ginstance, gtype))
        return NULL;

    return ginstance;
}

/* returns a goops object of class (gtype->class type). this function exists for
 * gobject.c:scm_c_gtype_instance_instance_init. all other callers should use
 * scm_c_gtype_instance_to_scm. */
SCM
scm_c_gtype_instance_to_scm_typed (gpointer ginstance, GType type)
{
    SCM class, object;

    object = scm_c_gtype_instance_get_cached (ginstance);
    if (!scm_is_false (object))
        return object;
    
    class = scm_c_gtype_lookup_class (type);
    if (SCM_FALSEP (class))
        class = scm_c_gtype_to_class (type);
    g_assert (SCM_NFALSEP (class));

    /* FIXME more comments on why we do it this way */
    object = scm_call_2 (_allocate_instance, class, SCM_EOL);
    scm_c_gtype_instance_bind_to_object (ginstance, object);
    scm_call_2 (_initialize, object, SCM_EOL);
    
    return object;
}

SCM
scm_c_gtype_instance_to_scm (gpointer ginstance)
{
    if (!ginstance)
        return SCM_BOOL_F;

    return scm_c_gtype_instance_to_scm_typed
        (ginstance, G_TYPE_FROM_INSTANCE (ginstance));
}



/**********************************************************************
 * Miscellaneous
 **********************************************************************/

void scm_c_gruntime_error (const char *subr, const char *message,
                           SCM args)
{
    scm_error (sym_gruntime_error, subr, message,
               args, SCM_EOL);
}



/**********************************************************************
 * Initialization
 **********************************************************************/

void
scm_init_gnome_gobject_types (void)
{
    g_type_init ();

#ifndef SCM_MAGIC_SNARFER
#include "gtype.x"
#endif

    quark_type = g_quark_from_static_string ("%scm-gtype->type");
    quark_class = g_quark_from_static_string ("%scm-gtype->class");
    quark_guile_gtype_class = g_quark_from_static_string ("%scm-guile-gtype-class");
    guile_gobject_quark_wrapper = g_quark_from_static_string ("%guile-gobject-wrapper");

    scm_sys_gtype_to_class =
        scm_permanent_object (SCM_VARIABLE_REF (scm_c_lookup ("%gtype->class")));

    _gtype_name_to_scheme_name = 
        scm_permanent_object (SCM_VARIABLE_REF (scm_c_lookup ("gtype-name->scheme-name")));
    _gtype_name_to_class_name = 
        scm_permanent_object (SCM_VARIABLE_REF (scm_c_lookup ("gtype-name->class-name")));

    _make_class = scm_permanent_object (SCM_VARIABLE_REF (scm_c_lookup ("make-class")));
    _class_redefinition =
        scm_permanent_object (SCM_VARIABLE_REF (scm_c_lookup ("class-redefinition")));
    _allocate_instance =
        scm_permanent_object (SCM_VARIABLE_REF (scm_c_lookup ("allocate-instance")));
    _initialize =
        scm_permanent_object (SCM_VARIABLE_REF (scm_c_lookup ("initialize")));
}

void
scm_init_gnome_gobject_types_gtype_class (void)
{
    scm_class_gtype_class = scm_permanent_object
	(SCM_VARIABLE_REF (scm_c_lookup ("<gtype-class>")));
}

void
scm_init_gnome_gobject_types_gtype_instance (void)
{
    scm_class_gtype_instance = scm_permanent_object
	(SCM_VARIABLE_REF (scm_c_lookup ("<gtype-instance>")));
}
