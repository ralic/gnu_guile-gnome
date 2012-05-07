;; guile-gnome
;; Copyright (C) 2007, 2011 Free Software Foundation

;; This program is free software; you can redistribute it and/or    
;; modify it under the terms of the GNU General Public License as   
;; published by the Free Software Foundation; either version 2 of   
;; the License, or (at your option) any later version.              
;;                                                                  
;; This program is distributed in the hope that it will be useful,  
;; but WITHOUT ANY WARRANTY; without even the implied warranty of   
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the    
;; GNU General Public License for more details.                     
;;                                                                  
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, contact:
;;
;; Free Software Foundation           Voice:  +1-617-542-5942
;; 59 Temple Place - Suite 330        Fax:    +1-617-542-2652
;; Boston, MA  02111-1307,  USA       gnu@gnu.org

;;; Commentary:
;;
;; This module exports two high-level procedures to transform the
;; Docbook files generated by GTK-Doc into texinfo.
;;
;; @uref{http://www.gtk.org/gtk-doc/,GTK-Doc} is commonly used to
;; document GObject-based libraries, such as those that Guile-GNOME
;; wraps. In a typical build setup, GTK-Doc generates a reference manual
;; with one XML file per section. The routines in this module attempt to
;; recreate those sections, but in Texinfo instead of Docbook, and which
;; document the Scheme modules instead of the upstream C libraries.
;;
;; The tricky part of translating GTK-Doc's documentation is not the
;; vocabulary (Docbook), but that it documents C functions which have
;; different calling conventions than Scheme. For example, a C function
;; might take four @code{double*} arguments, but in Scheme the function
;; would return four rational values. Given only the C prototype, the
;; code in this module will make an attempt to determine what the Scheme
;; function's arguments will be based on some heuristics.
;;
;; In most cases, however, we can do better than heuristics, because we
;; have the G-Wrap information that describes the relationship between
;; the C function and the Scheme wrapper. In that way we can know
;; exactly what the input and output arguments are for a particular
;; function.
;;
;; The @code{gtk-doc->texi-stubs} function is straightforward. It
;; extracts the "header" in a set of GTK-Doc files, translates them into
;; texinfo, writing them out one by one to files named
;; @samp{section-@var{foo}.texi}, where @var{foo} is the name of the XML
;; file. It is unclear whether it is best to continously generate these
;; sections when updating the manuals, or whether this "stub" generation
;; should be run only once when the documentation is initially
;; generated, and thereafter maintained by hand. Your call!
;;
;; @code{gtk-doc->texi-defuns} is slightly more complicated, because you
;; have the choice as to whether to use heuristics or the g-wrap method
;; for determining the arguments. See its documentation for more
;; information.
;;
;; Both of these functions are designed to be directly callable from the
;; shell. Here is a makefile snippet suitable for using the heuristics
;; method for defuns generation:
;;
;; @example
;; GTK_DOC_TO_TEXI_STUBS = \
;;   '((@@ (gnome gw support gtk-doc) gtk-doc->texi-stubs) \
;;   (cdr (program-arguments)))'
;; GTK_DOC_DEFUN_METHOD = heuristics
;; GTK_DOC_DEFUN_ARGS = (your-module-here)
;; GTK_DOC_TO_TEXI_DEFUNS = "(apply (@@ (gnome gw support gtk-doc) \
;;    gtk-doc->texi-defuns) (cadr (program-arguments)) \
;;    '$(GTK_DOC_DEFUN_METHOD) '($(GTK_DOC_DEFUN_ARGS)) \
;;    (cddr (program-arguments)))"
;; GUILE = $(top_builddir)/dev-environ guile
;;
;; generate-stubs:
;;      $(GUILE) $(GUILE_FLAGS) -c $(GTK_DOC_TO_TEXI_STUBS) \
;;         $(docbook_xml_files)
;;
;; generate-defuns:
;; 	$(GUILE) $(GUILE_FLAGS) -c $(GTK_DOC_TO_TEXI_DEFUNS) \
;;         ./overrides.texi $(docbook_xml_files)
;; @end example
;;
;; To make the above snippet work, you will have to define
;; @code{$(docbook_xml_files)} as the set of docbook XML files to
;; transform. To use the G-Wrap method, try the following:
;;
;; @example
;; wrapset_module = (gnome gw $(wrapset_stem)-spec)
;; wrapset_name = gnome-$(wrapset_stem)
;; GTK_DOC_DEFUN_METHOD = g-wrap
;; GTK_DOC_DEFUN_ARGS = $(wrapset_module) $(wrapset_name)
;; @end example
;;
;; Set @code{$(wrapset_stem)} to the stem of the wrapset name, e.g.
;; @code{pango}, and there you are.
;;
;;; Code:

(define-module (gnome gw support gtk-doc)
  #:use-module (sxml ssax)
  #:use-module ((sxml xpath) #:select (sxpath))
  #:use-module (sxml transform)
  #:use-module (ice-9 regex)
  #:use-module ((srfi srfi-1)
                #:select (append-map (fold . srfi-1:fold) lset-difference))
  #:use-module (srfi srfi-13)

  #:use-module (texinfo)
  #:use-module (texinfo docbook)
  #:use-module (texinfo reflection)
  #:use-module (texinfo serialize)
  #:use-module (match-bind)

  #:use-module (g-wrap)
  #:use-module (g-wrap guile) ;; for the `module' generic
  #:use-module (gnome gobject)
  #:use-module (gnome gobject utils)
  #:use-module (oop goops)

  #:use-module (gnome gobject utils)

  #:export (gtk-doc->texi-stubs
            gtk-doc->texi-defuns
            check-documentation-coverage
            generate-undocumented-texi))

(define (attr-ref attrs name . default)
  (or (and=> (assq name (cdr attrs)) cadr)
      (if (pair? default)
          (car default)
          (error "missing attribute" name))))

;; Make SSAX understand &nbsp; and &percnt; -- nasty, but that's how it
;; is
(for-each
 (lambda (pair)
   (cond-expand
    (guile-2
     (define-parsed-entity! (car pair) (cdr pair)))
    (else
     (set! ssax:predefined-parsed-entities
           (assoc-set! ssax:predefined-parsed-entities
                       (car pair) (cdr pair))))))
 '((nbsp . " ")
   (percnt . "%")
   (oacute . "ó")
   (sol . "/")
   (mdash . "&#x2014;")
   (ast . "&#x002A;")
   (num . "&#x0023;")
   (times . "✕")
   (ldquo . "“")
   (rdquo . "”")
   (hash . "#")))

(define (zap-whitespace sxml)
  (define (not-whitespace x)
    (or (not (string? x))
        (not (string-every char-whitespace? x))))
  (pre-post-order sxml
                  `((*default* . ,(lambda (tag . body)
                                    (cons tag
                                          (filter not-whitespace body))))
                    (*text* . ,(lambda (tag text) text)))))
                                                     
(define (docbook->sdocbook docbook-fragment)
  "Parse a docbook file @var{docbook-fragment} into SXML. Simply calls
SSAX's @code{xml->sxml}, but having made sure that @samp{&nbsp;} 
elements are interpreted correctly. Does not deal with XInclude."
  (zap-whitespace
   (call-with-input-file docbook-fragment
     (lambda (port) (ssax:xml->sxml port '())))))

(define (sdocbook-fold-defuns proc seed sdocbook-fragment)
  "Fold over the defuns in the gtk-doc-generated docbook fragment
@var{sdocbook-fragment}. Very dependent on the form of docbook that
gtk-doc emits."
  (let lp ((in ((sxpath '(refentry
                          refsect1
                          (refsect2 (@ 
                                     role
                                     (equal? "function")))))
                sdocbook-fragment))
           (seed seed))
    (if (null? in)
        seed
        (lp (cdr in) (proc (car in) seed)))))

(define (sdocbook-fold-structs proc seed sdocbook-fragment)
  "Fold over the struct definitions in the gtk-doc-generated docbook
fragment @var{sdocbook-fragment}. Very dependent on the form of docbook
that gtk-doc emits. Normally this corresponds to the set of classes
exported by the module, although it can contain other things."
  (let lp ((in (map cddr ((sxpath '(refentry refsect1 refsect2
                                    (title (anchor @ role
                                            (equal? "struct")))))
                          sdocbook-fragment)))
           (seed seed))
    (cond
     ((null? in) seed)
     ((and (pair? (car in)) (string? (caar in)))
      (lp (cdr in) (proc (caar in) seed)))
     (else
      (lp (cdr in) seed)))))

(define (identity . args) args)

(define strip-final-parens (s/// " *\\(\\)$" ""))

(define *gtk-doc-sdocbook->stexi-rules*
  `((variablelist
     ((varlistentry
       . ,(lambda (tag term . body)
            `(entry (% (heading ,@(cdr term))) ,@body)))
      (listitem
       . ,(lambda (tag . rest)
            (cond ((null? rest)
                   (warn "null listitem")
                   '(*fragment*))
                  ((pair? (car rest))
                   (if (not (null? (cdr rest)))
                       (warn "ignoring listitem extra contents:" (cddr rest)))
                   (car rest))
                  (else
                   (list 'para rest))))))
     . ,(lambda (tag attrs . body)
          `(table (% (formatter (var))) ,@body)))
    (term
     . ,(lambda (tag param . rest)
          (if (pair? param)
              param
              (list 'var param))))
    (parameter
     . ,(lambda (tag body)
          `(var ,(gtype-name->scheme-name body))))
    (type
     . ,(lambda (tag body)
          `(code ,(if (string? body)
                      (symbol->string (gtype-name->class-name body))
                      body))))
    (function
     . ,(lambda (tag body . ignored)
          (or (null? ignored) (warn "ignored function tail" ignored))
          `(code ,(if (pair? body) body
                      (gtype-name->scheme-name (strip-final-parens body))))))
    (xref . ,(lambda (tag attrs)
               `(emph "(the missing figure, " ,(cadr (assq 'linkend (cdr attrs))))))
    (figure
     *preorder*
     . ,(lambda (tag attrs . body)
          `(para "(The missing figure, "  ,(cadr (assq 'id (cdr attrs))))))
    (indexterm
     *preorder*
     . ,(lambda (tag . body)
          (let ((entry (string-join
                        (apply append (map cdr body)) ", ")))
            (if (string-null? entry)
                #f
                `(cindex (% (entry ,entry)))))))
    (emphasis
     *preorder*
     . ,(lambda (tag . body)
          (if (and (pair? body)
                   (pair? (car body))
                   (eq? (caar body) '@))
              (if (assq 'role (cdar body))
                  ;; Ignore role = annotation.
                  ""
                  (begin
                    (warn "Ignoring emphasis attributes" (car body))
                    (cons 'emph
                          (map (lambda (x)
                                 (pre-post-order x *gtk-doc-sdocbook->stexi-rules*))
                               (cdr body)))))
              (cons 'emph
                    (map (lambda (x)
                           (pre-post-order x *gtk-doc-sdocbook->stexi-rules*))
                         body)))))
    (*text*
     . ,(lambda (tag text)
          (or (assoc-ref '(("NULL" . (code "#f"))
                           ("FALSE" . (code "#f"))
                           ("TRUE" . (code "#t"))
                           ("Returns" . "ret")) text)
              text)))
    ,@*sdocbook->stexi-rules*))

(define *gtk-doc-sdocbook->stexi-desc-rules*
  `((link
     . ,(lambda (tag args body)
          body))
    ,@*gtk-doc-sdocbook->stexi-rules*))

(define (gtk-doc-sdocbook-title sdocbook)
  "Extract the title from a fragment of docbook, as produced by gtk-doc.
May return @code{#f} if the title is not found."
  (let ((l ((sxpath '(refentry refnamediv refname)) sdocbook)))
    (if (null? l)
        #f
        (cdar l))))

(define (gtk-doc-sdocbook-subtitle sdocbook)
  "Extract the subtitle from a fragment of docbook, as produced by gtk-doc.
May return @code{#f} if the subtitle is not found."
  (let ((l ((sxpath '(refentry refnamediv refpurpose)) sdocbook)))
    (if (null? l)
        #f
        (cdar l))))

(define (sdocbook-description sdocbook)
  (filter-empty-elements
   (replace-titles
    (sdocbook-flatten
     (cons '*fragment*
           (let ((fragments ((sxpath '(refentry
                                       (refsect1 (@ role (equal? "desc")))
                                       *))
                             sdocbook)))
             (if (and (pair? fragments) (pair? (car fragments))
                      (eq? (caar fragments) 'title))
                 ;; cdr past title... ugh.
                 (cdr fragments)
                 fragments)))))))
   
(define (gtk-doc-sdocbook->description-fragment sdocbook)
  "Extract the \"description\" of a module from a fragment of docbook,
as produced by gtk-doc, translated into texinfo."
  (cons '*fragment*
        (map
         (lambda (x)
           (pre-post-order x *gtk-doc-sdocbook->stexi-desc-rules*))
         (sdocbook-description sdocbook))))

(define (gtk-doc->texi-stubs files)
  "Generate a section overview texinfo file for each docbook XML file in
@var{files}.

The files will be created in the current directory, as described in the
documentation for @code{(gnome gw support gtk-doc)}. They will include a
file named @code{defuns-@var{file}.texi}, which should probably be
created using @code{gtk-doc->texi-defuns}."
  (for-each
   (lambda (file)
     (let* ((sdocbook (docbook->sdocbook file))
            (basename (basename file))
            (title (gtk-doc-sdocbook-title sdocbook))
            (subtitle (gtk-doc-sdocbook-subtitle sdocbook))
            (desc (gtk-doc-sdocbook->description-fragment sdocbook)))
       (if title
           (with-output-to-file (string-append "section-" basename ".texi")
             (lambda ()
               (display
                (stexi->texi
                 `(*fragment*
                   (node (% (name ,@title)))
                   (chapter ,@title)
                   ,@(if subtitle `((para ,@subtitle)) '())
                   (section "Overview")
                   ,@(cdr desc)
                   (section "Usage")
                   (include ,(string-append "defuns-" basename ".texi"))))))))))
   files))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; The following functions try to parse out the arguments from the
;; preformatted function definition produced by gtk-doc. It uses
;; heuristics, necessarily. The culmination of this effort is
;; make-deffn-args, called in *gtk-doc-sdocbook->stexi-def-rules*.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (string-value xml)
  ;; inefficient, but hey!
  (cond ((symbol? xml) "")
        ((string? xml) xml)
        ((pair? xml)
         (if (eq? (car xml) '@)
             ""
             (apply string-append (map string-value xml))))))

(define (parse-deffn-args elt)
  (define (trim-const type)
    (match-bind "^(const )?(.*)$" type (_ const rest)
                rest))
  (define (parse-arg arg args)
    ;; ignores const.
    (match-bind "^(.*) (\\**)([^ ]+)$" arg (_ type stars name)
                (acons (string-append (trim-const
                                       (string-trim-both type))
                                      stars)
                       name
                       args)
                (cond ((string=? "void" arg) args)
                      ((string=? "void" arg) args)
                      (else (error "could not parse" arg)))))
  (let ((flat (string-value elt)))
    (match-bind "^(.*?) ([^ ]+) +\\((.*)\\);" flat (_ ret-type name args)
                `((data-type
                   . ,(trim-const (string-trim-both ret-type)))
                  (name
                   . ,name)
                  (arguments
                   . ,(reverse
                       (srfi-1:fold
                        parse-arg
                        '()
                        (map string-trim-both
                             (string-split args #\,)))))))))

(define *immediate-types*
  '("double"))

(define (output-type? type)
  (let* ((base (substring type 0 (or (string-index type #\*)
                                    (string-length type))))
         (nstars (string-length (substring type (string-length base)))))
    (> nstars 
       (if (member base *immediate-types*) 0 1))))

(define (strip-star type)
  (let ((len (string-length type)))
    (if (eqv? (string-ref type (1- len)) #\*)
        (substring type 0 (1- len))
        type)))

(define (c-arguments->scheme-arguments args return-type)
  (define (arg-texinfo arg)
    `(" (" (var ,(gtype-name->scheme-name (cdr arg))) (tie)
      (code ,(symbol->string
              (gtype-name->class-name (strip-star (car arg))))) ")"))
  (define (finish input-args output-args)
    (let ((inputs (append-map arg-texinfo input-args))
          (outputs (append-map arg-texinfo
                               (if (string=? return-type "void")
                                   output-args
                                   (acons return-type "ret" output-args)))))
      (if (null? outputs)
          inputs
          (append inputs '(" " (result) (tie)) outputs))))
  (let lp ((args args) (out '()))
    (cond
     ((null? args)
      (finish (reverse out) '()))
     ((output-type? (caar args))
      (finish (reverse out) args))
     (else
      (lp (cdr args) (cons (car args) out))))))

(define (make-deffn-args elt)
  (let ((args (parse-deffn-args elt)))
    `(% (category "Function")
        (name ,(gtype-name->scheme-name (assq-ref args 'name)))
        (arguments ,@(c-arguments->scheme-arguments 
                      (assq-ref args 'arguments)
                      (assq-ref args 'data-type))))))
                      
(define *gtk-doc-sdocbook->stexi-def-rules*
  `((refsect2
     *macro*
     . ,(lambda (tag . body)
          (let lp ((body body))
            (let ((elt (car body)))
              (if (and (pair? elt) (eq? (car elt) 'programlisting))
                  `(deffn ,(make-deffn-args elt)
                     ,@(filter-empty-elements
                        (replace-titles
                         (sdocbook-flatten
                          (cons '*fragment* (cdr body))))))
                  (lp (cdr body)))))))
    (deffn
      . ,identity)
    (link
     . ,(lambda (tag args body)
          body))
    ,@*gtk-doc-sdocbook->stexi-rules*))

(define (gtk-doc-sdocbook->def-list/heuristics sdocbook process-def)
  (reverse
   (sdocbook-fold-defuns
    (lambda (fragment seed)
      (let* ((parsed (pre-post-order
                      fragment *gtk-doc-sdocbook->stexi-def-rules*))
             (name (string->symbol (attr-ref (cadr parsed) 'name)))
             (def (process-def name parsed)))
        (if def
            (cons def seed)
            seed)))
    '()
    sdocbook)))

(define (input-arg-names func)
  (map name (input-arguments func)))
(define (input-arg-type-names func)
  (map name (map type (map typespec (input-arguments func)))))
(define (output-arg-names func)
  (map name (output-arguments func)))
(define (output-arg-type-names func)
  (map name (map type (map typespec (output-arguments func)))))
(define (return-type-name func)
  (name (return-type func)))

(define (make-function-hash wrapset)
  (let ((ret (make-hash-table)))
    (fold-functions
     (lambda (f nil)
       (let ((in (input-arguments f))
             (out (output-arguments f)))
         (hashq-set! ret (name f) f)))
     #f
     wrapset)
    ret))

(define (parse-func-name elt)
  (string->symbol
   (gtype-name->scheme-name
    (let ((flat (string-value elt)))
      (match-bind "^(.*?) ([^ ]+) +\\((.*)\\);"
                  flat (_ ret-type name args)
                  name
                  (error "could not parse" flat))))))

(define (function-stexi-arguments f)
  (define (arg-texinfo name type)
    `(" (" ,(symbol->string name) (tie)
      (code ,(symbol->string type)) ")"))
  (let ((inputs (append-map arg-texinfo (input-arg-names f)
                            (input-arg-type-names f)))
        (outputs (apply append-map arg-texinfo
                        (if (eq? (return-type-name f) 'void)
                            (list (output-arg-names f)
                                  (output-arg-type-names f))
                            (list (cons 'ret
                                        (output-arg-names f))
                                  (cons (return-type-name f)
                                        (output-arg-type-names f)))))))
    (if (null? outputs)
        inputs
        (append inputs '(" " (result) (tie)) outputs))))

(define (make-defs/g-wrap elt funcs body process-def)
  (or
   (and=>
    (hashq-ref funcs (parse-func-name elt))
    (lambda (f)
      (let ((deffn (process-def
                    (name f)
                    `(deffn (% (name ,(symbol->string (name f)))
                               (category "Function")
                               (arguments
                                ,@(function-stexi-arguments f)))
                       ,@(map
                          (lambda (fragment)
                            (pre-post-order
                             fragment
                             *gtk-doc-sdocbook->stexi-def-rules*))
                          (filter-empty-elements
                           (replace-titles
                            (sdocbook-flatten
                             (cons '*fragment* body))))))))
            (generic (generic-name f)))
        (if generic
            `((,(car deffn)
               ,(cadr deffn)
               (deffnx (% (name ,(symbol->string generic))
                          (category "Method")))
               ,@(cddr deffn)))
            (list deffn)))))
   '()))

(define (gtk-doc-sdocbook->def-list/g-wrap sdocbook process-def wrapset)
  (let ((funcs (make-function-hash wrapset)))
    (reverse
     (sdocbook-fold-defuns
      (lambda (fragment seed)
        (append
         (let lp ((body fragment))
           (let ((elt (car body)))
             (if (and (pair? elt) (eq? (car elt) 'programlisting))
                 (reverse
                  (make-defs/g-wrap elt funcs (cdr body) process-def))
                 (lp (cdr body)))))
         seed))
      '()
      sdocbook))))

(define (signal-doc-name rs2)
  (let ((full-name (cadar ((sxpath '(indexterm primary)) rs2))))
    (substring full-name (1+ (string-index-right full-name #\:)))))

(define (signal-doc-docs rs2)
  (map
   (lambda (fragment)
     (pre-post-order
      fragment
      *gtk-doc-sdocbook->stexi-def-rules*))
   (filter-empty-elements
    (replace-titles
     (append-map
      sdocbook-flatten
      ((sxpath '(para)) rs2))))))

(define (signal-refsect2-list sdocbook)
  ((sxpath '(refentry (refsect1 (@ role (equal? "signals"))) refsect2))
   sdocbook))

(define (signal-docs-alist sdocbook)
  (map (lambda (rs2)
         (cons (signal-doc-name rs2)
               (signal-doc-docs rs2)))
       (signal-refsect2-list sdocbook)))

(define (signal-stexi-args s)
  (define (class->texi class)
    `(code ,(symbol->string (class-name class))))
  (define (arg-texinfo name class)
    `(" (" ,name (tie) ,(class->texi class) ")"))
  (with-accessors (param-types return-type)
    (let ((inputs (append-map arg-texinfo
                              (map (lambda (i)
                                     (string-append "arg" (number->string i)))
                                   (iota (length (param-types s))))
                              (param-types s)))
          (outputs (let ((type (return-type s)))
                     (if (not type)
                         '()
                         (list (class->texi type))))))
      (if (null? outputs)
          inputs
          (append inputs '(" " (result) (tie)) outputs)))))

(define (class-signal-stexi-docs class sdocbook)
  (let ((alist (signal-docs-alist sdocbook)))
    (map
     (lambda (s)
       (with-accessors (name)
         `(defop (% (category "Signal")
                    (name ,(name s))
                    (class ,(symbol->string (class-name class)))
                    (arguments ,@(signal-stexi-args s)))
            ,@(or (assoc-ref alist (name s)) '("undocumented")))))
     (if (is-a? class <gtype-class>)
         (with-accessors (interface-type)
           (filter (lambda (signal) (eq? (interface-type signal) class))
                   (gtype-class-get-signals class)))
         '()))))

(define (superclasses class)
  (define (list-join l infix)
    "Infixes @var{infix} into list @var{l}."
    (if (null? l) l
        (let lp ((in (cdr l)) (out (list (car l))))
          (cond ((null? in) (reverse out))
                (else (lp (cdr in) (cons* (car in) infix out)))))))
  (cond
   ((is-a? class <class>)
    `(para
      "Derives from "
      ,@(list-join
         (map (lambda (namesym) `(code ,(symbol->string namesym)))
              (map class-name (class-direct-supers class)))
         ", ")
      "."))
   (else
    '(para "Opaque pointer."))))

(define (gobject-class-stexi-docs module-name class-name sdocbook)
  (define (doc-slots class)
    (define (doc-slot slot)
      (let ((name (slot-definition-name slot)))
        `(entry
          (% (heading ,(symbol->string name)))
          (para
           ,(case (slot-definition-allocation slot)
              ((#:gproperty #:gparam)
               (with-accessors (blurb)
                 (blurb (gobject-class-find-property class name))))
              (else
               "Scheme slot."))))))
    (let ((slots (if (is-a? class <class>)
                     (class-direct-slots class)
                     '()))) ;; silliness regardings wcts...
      (cond
       ((null? slots)
        '((para "This class defines no direct slots.")))
       (else
        `((para "This class defines the following slots:")
          (table (% (formatter (code)))
                 ,@(map doc-slot slots)))))))
  (let ((v (module-variable (resolve-interface module-name) class-name)))
    (cond
     (v
      `((deftp (% (name ,(symbol->string class-name))
                  (category "Class"))
          ,(superclasses (variable-ref v))
          ,@(doc-slots (variable-ref v)))
        ,@(class-signal-stexi-docs (variable-ref v) sdocbook)))
     (else
      '()))))

(define (make-type-docs? class-name wrapset)
  ;; does the type (1) exist and (2) define an export?
  (fold-types (lambda (x y)
                (or y (and (eq? (name x) class-name)
                           (or (not (slot-exists? x 'define-class?))
                               (slot-ref x 'define-class?)))))
              #f wrapset))

(define (gtk-doc-sdocbook->class-list/g-wrap sdocbook process-def wrapset)
  (reverse
   (sdocbook-fold-structs
    (lambda (cname seed)
      (let ((class-name (gtype-name->class-name cname)))
        (cond
         ((make-type-docs? class-name wrapset)
          (append (reverse
                   (gobject-class-stexi-docs (module wrapset) class-name
                                             sdocbook))
                  seed))
         (else
          seed))))
    '()
    sdocbook)))

(define (gtk-doc->texi-defuns/g-wrap sdocbook defs-alist module-name
                                     wrapset-name)
  ;; load up the wrapset definition from the module
  (resolve-interface module-name)
  (let ((wrapset (get-wrapset 'guile wrapset-name)))
    (define (munge-def name def)
      (or (and=> (assq name defs-alist) cdr) def))
    (append
     (gtk-doc-sdocbook->class-list/g-wrap sdocbook munge-def wrapset)
     (gtk-doc-sdocbook->def-list/g-wrap sdocbook munge-def wrapset))))

(define (gtk-doc->texi-defuns/heuristics sdocbook defs-alist module-name)
  (let ((interface (resolve-interface module-name)))
    (define (munge-def name def)
      (and (module-variable interface name)
           (or (and=> (assq name defs-alist) cdr) def)))
    (gtk-doc-sdocbook->def-list/heuristics sdocbook munge-def)))

(define *gtk-doc->texi-defuns-methods*
  `((g-wrap . ,gtk-doc->texi-defuns/g-wrap)
    (heuristics . ,gtk-doc->texi-defuns/heuristics)))

(define (def-name def)
  (string->symbol (cadr (assq 'name (cdadr def)))))

(define (gtk-doc->texi-defuns overrides method args . files)
  "Generate documentation for the types and functions defined in a set
of docbook files genearted by GTK-Doc.

@var{overrides} should be a path to a texinfo file from which
@code{@@deffn} overrides will be taken. @var{method} should be either
@code{g-wrap} or @code{heuristics}, as discussed in the @code{(gnome gw
support gtk-doc)} documentation. @var{files} is the list of docbook XML
files from which to pull function documentation.

@var{args} should be a list, whose form depends on the @var{method}. For
@code{g-wrap}, it should be two elements, the first the name of a module
that, when loaded, will load the necessary wrapset into the g-wrap
runtime. For example, @code{(gnome gw glib-spec)}. The second argument
should be the name of the wrapset, e.g. @code{gnome-glib}.

If @var{method} is @code{heuristics}, @var{args} should have only one
element, the name of the module to load to check the existence of
procedures, e.g. @code{(cairo)}."
  (let* ((defs ((sxpath '(deffn))
                (call-with-input-file overrides texi-fragment->stexi)))
         (defs-alist (map cons (map def-name defs) defs))
         (make-defuns (or (assq-ref *gtk-doc->texi-defuns-methods* method)
                          (error "unknown method" method))))
    (for-each
     (lambda (file)
       (let* ((sdocbook (docbook->sdocbook file))
              (basename (basename file))
              (docs (stexi->texi
                     `(*fragment*
                       ,@(apply make-defuns sdocbook defs-alist args)))))
         (with-output-to-file (string-append "defuns-" basename ".texi")
           (lambda ()
             (display docs)))))
     files)))

(define (symbolcomp pred)
  (lambda (a b)
    (pred (symbol->string a) (symbol->string b))))

(define symbol<?
  (symbolcomp string<?))

(define (extract-defs stexi)
  (let ((commands (srfi-1:fold
                   (lambda (def rest)
                     (if (string-prefix? "def" (symbol->string (car def)))
                         (cons (car def) rest)
                         rest))
                        '() texi-command-specs)))
    (srfi-1:fold
     (lambda (x rest)
       (if (and (pair? x) (memq (car x) commands))
           (cons x rest)
           rest))
     '() stexi)))

(define (check-documentation-coverage modules texi)
  "Check the coverage of generated documentation.

@var{modules} is a list of module names, and @var{texi} is a path to
a texinfo file. The set of exports of @var{modules} is checked against
the set of procedures defined in @var{texi}, resulting in a calculation
of documentation coverage, and the output of any missing documentation
to the current output port."
  (let* ((defs (extract-defs
                (call-with-input-file texi texi->stexi)))
         (def-names (map def-name defs))
         (exports (append-map
                   (lambda (mod)
                     (or
                      (false-if-exception
                       (module-map (lambda (k v) k)
                                   (resolve-interface mod)))
                      (begin (warn "Module does not exist:" mod) '())))
                   modules))
         (undocumented (lset-difference eq? exports def-names))
         (spurious (lset-difference eq? def-names exports)))
    (format #t "~A symbols exported\n" (length exports))
    (format #t "~A symbols documented\n" (length def-names))
    (format #t "~A symbols undocumented\n" (length undocumented))
    (for-each
     (lambda (sym)
       (format #t "  ~A\n" sym))
     (sort undocumented symbol<?))
    (format #t "~A symbols spuriously documented\n" (length spurious))
    (for-each
     (lambda (sym)
       (format #t "  ~A\n" sym))
     (sort spurious symbol<?))))

(define (generate-undocumented-texi modules texi)
  "Verify the bindings exported by @var{modules} against the
documentation in @var{texi}, writing documentation for any undocumented
symbol to @code{undocumented.texi}.

@var{modules} is a list of module names, and @var{texi} is a path to a
texinfo file."
  (let* ((defs (extract-defs
                (call-with-input-file texi texi->stexi)))
         (def-names (map def-name defs)))
    (define (module-undocumented mod)
      (sort! 
       (lset-difference eq?
                        (module-map (lambda (k v) k)
                                    (resolve-interface mod))
                        def-names)
       symbol<?))
    (display
     (stexi->texi
      `(*fragment*
        (node (% (name "Undocumented")))
        (chapter "Undocumented")
        (para "The following symbols, if any, have not been properly "
              "documented.")
        ,@(append-map
           (lambda (mod)
             (let ((undocumented (module-undocumented mod)))
               (cond
                ((null? undocumented) '())
                (else
                 `((section ,(with-output-to-string
                               (lambda () (write mod))))
                   ,@(append-map
                      (lambda (sym)
                        (let ((odoc (object-stexi-documentation
                                     (module-ref (resolve-interface mod) sym)
                                     sym
                                     #:force #t)))
                          (if (eq? (car odoc) '*fragment*)
                              (cdr odoc)
                              (list odoc))))
                      undocumented))))))
           modules)))
     (open-output-file "undocumented.texi"))))
