#include "gstreamer-support.h"

#define GRUNTIME_ERROR(format, func_name, args...) \
  scm_error (scm_str2symbol ("gruntime-error"), func_name, format, \
             ##args, SCM_EOL)


/***********************************************************************
 * GstBin
 */

static GQuark quark_iterator = 0;

void
gst_bin_attach_iterator (GstBin *bin) 
{
  if (!quark_iterator)
    quark_iterator = g_quark_from_static_string ("%bin-iterator");

  /* FIXME: do I need to ref the bin? */
  g_object_set_qdata_full ((GObject*)bin,
                           quark_iterator,
                           GINT_TO_POINTER (g_idle_add ((GSourceFunc)gst_bin_iterate,
                                                        bin)),
                           (GDestroyNotify)g_source_remove);
}

void
gst_bin_remove_iterator (GstBin *bin) 
{
  guint source_id = 0;

  if (quark_iterator)
    source_id = GPOINTER_TO_INT (g_object_get_qdata ((GObject*)bin, quark_iterator));

  if (!source_id)
    GRUNTIME_ERROR ("Bin has no iterator attached", "gst-bin-remove-iterator",
                    SCM_BOOL_F);

  g_object_set_qdata ((GObject*)bin, quark_iterator, NULL);
}


/***********************************************************************
 * GstBuffer
 */

/* Silly function used not to modify the semantics of the silly
 * prototype system in order to be backward compatible.
 */
static int
singp (SCM obj)
{
  if (!SCM_SLOPPY_REALP (obj))
    return 0;
  else
    {
      double x = SCM_REAL_VALUE (obj);
      float fx = x;
      return (- SCM_FLTMAX < x) && (x < SCM_FLTMAX) && (fx == x);
    }
}

/* code stolen from unif.c:scm_make_uve */
SCM
_wrap_gst_buffer_get_data (GstBuffer *buf, SCM prot)
#define FUNC_NAME "gst-buffer-get-data"
{
  SCM v;
  long i, type, k;

  if (GST_BUFFER_SIZE (buf) == 0 || GST_BUFFER_DATA (buf) == NULL)
    return SCM_BOOL_F;

  i = GST_BUFFER_SIZE (buf);

  if (SCM_EQ_P (prot, SCM_BOOL_T))
    {
      GRUNTIME_ERROR ("Sorry, can't represent a GstBuffer as a bit vector.",
                      "gst-buffer-get-data", SCM_EOL);
    }
  else if (SCM_CHARP (prot))
    {
      k = i / sizeof (char);
      type = scm_tc7_byvect;
    }
  else if (SCM_INUMP (prot))
    {
      k = i / sizeof (long);
      if (SCM_INUM (prot) > 0)
	type = scm_tc7_uvect;
      else
	type = scm_tc7_ivect;
    }
  else if (SCM_SYMBOLP (prot) && (1 == SCM_SYMBOL_LENGTH (prot)))
    {
      char s;

      s = SCM_SYMBOL_CHARS (prot)[0];
      if (s == 's')
	{
	  k = i / sizeof (short);
	  type = scm_tc7_svect;
	}
      else if (s == 'l')
	{
	  k = i / sizeof (long long);
	  type = scm_tc7_llvect;
	}
      else
	{
          GRUNTIME_ERROR ("Sorry, non-uniform vectors are not supported.",
                          "gst-buffer-get-data", SCM_EOL);
	}
    }
  else if (!SCM_INEXACTP (prot))
    {
      GRUNTIME_ERROR ("Sorry, non-uniform vectors are not supported.",
                      "gst-buffer-get-data", SCM_EOL);
    }
  else if (singp (prot))
    {
      k = i / sizeof (float);
      type = scm_tc7_fvect;
    }
  else if (SCM_COMPLEXP (prot))
    {
      k = i / 2 / sizeof (double);
      type = scm_tc7_cvect;
    }
  else
    {
      k = i / sizeof (double);
      type = scm_tc7_dvect;
    }

  SCM_ASSERT_RANGE (1, scm_long2num (k), k <= SCM_UVECTOR_MAX_LENGTH);

  if (i % k)
    GRUNTIME_ERROR ("The length of this buffer is not cleanly divisable by the specified prototype.",
                    "gst-buffer-get-data", scm_long2num (i));

  SCM_NEWCELL (v);
  SCM_DEFER_INTS;
  SCM_SET_UVECTOR_BASE (v, GST_BUFFER_DATA (buf));
  SCM_SET_UVECTOR_LENGTH (v, k, type);
  SCM_ALLOW_INTS;
  return scm_gc_protect_object (v); /* a hack memleak until other issues are
                                     * solved */

  /* memory management issues:
     1) need to protect the data from being freed -- it does not belong to the
        vector.
     2) the vector may not be accessed after gst_pad_push is called.
  */
}
#undef FUNC_NAME

void
_wrap_gst_buffer_set_data (GstBuffer *buf, SCM uvect)
{
  long width;
  
  switch (SCM_TYP7 (uvect)) {
  case scm_tc7_byvect:
    width = sizeof (char);
    break;
  case scm_tc7_uvect:
  case scm_tc7_ivect:
    width = sizeof (long);
    break;
  case scm_tc7_svect:
    width = sizeof (short);
    break;
  case scm_tc7_llvect:
    width = sizeof (long long);
    break;
  case scm_tc7_fvect:
    width = sizeof (float);
    break;
  case scm_tc7_dvect:
    width = sizeof (double);
    break;
  case scm_tc7_cvect:
    width = 2 * sizeof (double);
    break;
  default:
    GRUNTIME_ERROR ("Invalid uniform vector type.", "gst-buffer-set-data", uvect);
  }

  GST_BUFFER_DATA (buf) = SCM_UVECTOR_BASE (uvect);
  GST_BUFFER_SIZE (buf) = SCM_UVECTOR_LENGTH (uvect) * width;
  /* temporary hack: we need our own bufferpool really */
  GST_BUFFER_FLAG_SET (buf, GST_BUFFER_DONTFREE);
  /* memory management issues:
     either we
       1) hold a reference on the vector passed in until the buffer is unreffed
       2) forget about the vector itself, just protect the data so it can be
          freed by gstreamer
     
     i guess it really depends on where the data comes from, whether it's
     originating in C or scheme. not sure what to do on this one.

     for now we can hack in a memleak and keep a hold on the vector.
  */
  scm_gc_protect_object (uvect);
}


/***********************************************************************
 * GstClock
 */

static gboolean
call_async_clock_wait (GstClock *clock, GstClockTime time, GstClockID id, SCM closure)
{
  /* should pass the clock as well... */
  return SCM_NFALSEP (scm_call_1 (scm_gc_unprotect_object (closure),
                                  scm_ulong_long2num (time)));
}

GstClockReturn
_wrap_gst_clock_id_wait_async (GstClockID id,
                               SCM callback)
{
  return gst_clock_id_wait_async (id, (GstClockCallback)call_async_clock_wait,
                                  SCM_PACK (scm_gc_protect_object (callback)));
}


/***********************************************************************
 * GstPad
 */

typedef struct {
  SCM pad;
  SCM link_function;
  SCM chain_function;
  SCM get_function;
} GuileGstPadPrivate;

static GuileGstPadPrivate*
pad_private(GstPad *gpad, SCM pad)
{
  GuileGstPadPrivate* private;

  private = (GuileGstPadPrivate*)gst_pad_get_element_private (gpad);

  if (!private) {
    g_assert (SCM_NFALSEP (pad));

    /* FIXME free me sometime... */
    private = g_new (GuileGstPadPrivate, 1);
    private->pad = scm_gc_protect_object (pad);
    private->link_function = SCM_BOOL_F;
    private->chain_function = SCM_BOOL_F;
    private->get_function = SCM_BOOL_F;
    gst_pad_set_element_private (gpad, private);
  }

  return private;
}

#if GST_VERSION_MINOR < 7
#define PAD_DATA GstBuffer*
#else
#define PAD_DATA GstData*
#endif

static void
call_chain_function(GstPad *pad, PAD_DATA data)
{
  SCM scm_data;
  GuileGstPadPrivate *private;
  
  private = pad_private (pad, SCM_BOOL_F);
  /* even though it's really a GstData, there's no GstData type (right now, at
     least) */
  scm_data = scm_c_make_gvalue (GST_TYPE_BUFFER);
  g_value_set_boxed ((GValue*)SCM_SMOB_DATA (scm_data), data);

  scm_call_2 (private->chain_function, private->pad,
              scm_data);
}

void
_wrap_gst_pad_set_chain_function (SCM pad, SCM chain_function)
{
#define FUNC_NAME "gst-pad-set-chain-function"
  GObject *gpad;
  GuileGstPadPrivate *private;
  
  SCM_VALIDATE_GOBJECT_COPY (1, pad, gpad);
  SCM_ASSERT (GST_IS_PAD (gpad), pad, 1, FUNC_NAME);
  SCM_VALIDATE_PROC (2, chain_function);

  private = pad_private ((GstPad*)gpad, pad);
  if (SCM_NFALSEP (private->chain_function))
    scm_gc_unprotect_object (private->chain_function);

  private->chain_function = scm_gc_protect_object (chain_function);

  gst_pad_set_chain_function ((GstPad*)gpad, call_chain_function);
#undef FUNC_NAME
}

static PAD_DATA
call_get_function (GstPad *pad)
{
  SCM ret;
  GuileGstPadPrivate *private;
  GstBuffer *buffer;
  
  private = pad_private (pad, SCM_BOOL_F);

  ret = scm_call_1 (private->get_function, private->pad);
  if (SCM_TYP16_PREDICATE (scm_tc16_gvalue, ret)
      /* we check specifically for buffers and events, as boxed types don't know
         anything about inheritance */
      && (G_VALUE_HOLDS ((GValue*)SCM_SMOB_DATA (ret), GST_TYPE_BUFFER)
          || G_VALUE_HOLDS ((GValue*)SCM_SMOB_DATA (ret), GST_TYPE_EVENT)))
    return (PAD_DATA) (g_value_get_boxed ((GValue*)SCM_SMOB_DATA (ret)));
  
  GRUNTIME_ERROR ("Return from pad's get function should be a GstBuffer or a GstEvent",
                  "%gst-pad-get-function", ret);
  return NULL;
}

void
_wrap_gst_pad_set_get_function (SCM pad, SCM get_function)
{
#define FUNC_NAME "gst-pad-set-chain-function"
  GObject *gpad;
  GuileGstPadPrivate *private;
  
  SCM_VALIDATE_GOBJECT_COPY (1, pad, gpad);
  SCM_ASSERT (GST_IS_PAD (gpad), pad, 1, FUNC_NAME);
  SCM_VALIDATE_PROC (2, get_function);

  private = pad_private ((GstPad*)gpad, pad);
  if (SCM_NFALSEP (private->get_function))
    scm_gc_unprotect_object (private->get_function);

  private->get_function = scm_gc_protect_object (get_function);

  gst_pad_set_get_function ((GstPad*)gpad, call_get_function);
#undef FUNC_NAME
}

static GstPadLinkReturn
call_link_function(GstPad *pad, const GstCaps *caps)
{
  SCM scm_caps, ret;
  GuileGstPadPrivate *private = pad_private (pad, SCM_BOOL_F);
  
  scm_caps = scm_c_make_gvalue (GST_TYPE_CAPS);
  g_value_set_boxed ((GValue*)SCM_SMOB_DATA (scm_caps), caps);

  ret = scm_call_2 (private->link_function, private->pad,
                    scm_caps);

  if (SCM_INUMP (ret))
    return scm_num2int (ret, 0, "(pad link function)");
  else if (SCM_SYMBOLP (ret)) {
    GstPadLinkReturn r;
    GEnumValue *v = g_enum_get_value_by_name (g_type_class_peek (GST_TYPE_PAD_LINK_RETURN),
                                              SCM_SYMBOL_CHARS (ret));
    r = v->value;
    g_free (v);
    return r;
  } else
    scm_error (scm_str2symbol ("gruntime-error"), "(pad link function)",
               "Bad link function ~A return value: ~A (should be a symbol or number)",
               SCM_LIST2 (private->link_function, ret),
               SCM_EOL);

  return GST_PAD_LINK_REFUSED;
}

void
_wrap_gst_pad_set_link_function (SCM pad, SCM link_function)
{
#define FUNC_NAME "gst-pad-set-link-function"
  GObject *gpad;
  GuileGstPadPrivate *private;
  
  SCM_VALIDATE_GOBJECT_COPY (1, pad, gpad);
  SCM_ASSERT (GST_IS_PAD (gpad), pad, 1, FUNC_NAME);
  SCM_VALIDATE_PROC (2, link_function);

  private = pad_private ((GstPad*)gpad, pad);
  if (SCM_NFALSEP (private->link_function))
    scm_gc_unprotect_object (private->link_function);

  private->link_function = scm_gc_protect_object (link_function);

  gst_pad_set_link_function ((GstPad*)gpad, call_link_function);
#undef FUNC_NAME
}

static void
struct_for_each_func (GQuark id, GValue *value, SCM proc)
{
  GValue *tmp;
  SCM svalue;
  
  tmp = g_new0 (GValue, 1);
  g_value_init (tmp, G_VALUE_TYPE (value));
  g_value_copy (value, tmp);
  SCM_NEWSMOB (svalue, scm_tc16_gvalue, tmp);
  
  scm_call_2 (proc, scm_makfrom0str (g_quark_to_string (id)), svalue);
}
              
void
_wrap_gst_structure_for_each (GstStructure *str, SCM proc)
#define FUNC_NAME "gst-structure-for-each"
{
  SCM_VALIDATE_PROC (2, proc);

  gst_structure_foreach (str, (GstStructureForeachFunc)struct_for_each_func, proc);
}
#undef FUNC_NAME
