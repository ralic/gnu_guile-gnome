;; guile-gnome
;; Copyright (C) 2003,2004 Andy Wingo <wingo at pobox dot com>
;; Copyright (C) 2004 Andreas Rottmann <rotty at debian dot org>

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
;;A g-wrap specification for GObject.
;;
;;; Code:

;;; -*-scheme-*-

(define-module (gnome gw gobject-spec)
  #:use-module (oop goops)
  #:use-module (gnome gw support g-wrap)
  #:use-module (g-wrap enumeration)
  #:use-module (gnome gw glib-spec)
  #:use-module (gnome gw support gobject))

;; gw-gobject: a wrapset to assist in wrapping gobject-based apis

(define-class <gobject-wrapset> (<gobject-wrapset-base>)
  #:id 'gnome-gobject #:dependencies '(standard gnome-glib))

(define-class <include-item> (<gw-item>))

(define-method (global-declarations-cg (ws <gobject-wrapset>)
                                       (item <include-item>))
  (list "#include <guile-gnome-gobject.h>\n"))

(define-method (initializations-cg (ws <gobject-wrapset>) err)
  (list (next-method)
        (inline-scheme ws '(use-modules (gnome gobject)))))
   
(define-method (initialize (ws <gobject-wrapset>) initargs)
  (next-method ws (append '(#:module (gnome gw gobject)) initargs))
  
  (let ((item (make <include-item>)))
    (add-item! ws item)
    (add-client-item! ws item))
  
  (add-type! ws (make <gw-guile-simple-type>
                  #:name '<gtype>
                  #:c-type-name "GType"
                  #:type-check #f
                  #:unwrap '(c-var " = scm_c_gtype_class_to_gtype (" scm-var ");\n")
                  #:wrap '(scm-var " = scm_c_gtype_to_class (" c-var ");\n")
                  #:ffspec 'size_t))
  
  (wrap-instance! ws
                  #:name '<gobject>
                  #:ctype "GObject"
                  #:gtype-id "G_TYPE_OBJECT"
                  #:define-class? #f)

  (add-type! ws (make <gvalue-type>
                  #:name '<gvalue>
                  #:ctype "GValue"
                  #:c-type-name  "GValue*"
                  #:c-const-type-name "const GValue*"
                  #:ffspec 'pointer
                  #:wrapped "Custom"))

  (add-type! ws (make <gclosure-type>
                  #:gtype-id "G_TYPE_CLOSURE"
                  #:name '<gclosure>
                  #:ctype "GClosure"
                  #:c-type-name "GClosure*"
                  #:c-const-type-name "const GClosure*"
                  #:ffspec 'pointer
                  #:wrapped "Custom"
                  #:define-class? #f))
             
  (add-type! ws (make <gparam-spec-type>
                  #:name '<gparam>
                  #:ctype "GParamSpec"
                  #:c-type-name "GParamSpec*" 
                  #:c-const-type-name "const GParamSpec*"
                  #:ffspec 'pointer
                  #:wrapped "Custom"))
  
  (for-each
   (lambda (pair) (add-type-alias! ws (car pair) (cadr pair)))
   '(("GType" <gtype>)
     ("GValue*" <gvalue>)
     ("GObject*" <gobject>)
     ("GClosure*" <gclosure>)
     ("GParamSpec*" <gparam>)))
  
  (wrap-gobject-class!
   ws
   #:ctype "GObjectClass" #:gtype-id "G_TYPE_OBJECT")

  ;; Wrap the pariah function of gobject.
  (wrap-function!
   ws
   #:name        'g-source-set-closure
   #:returns     'void
   #:c-name      "g_source_set_closure"
   #:arguments   '((<g-source> source) ((<gclosure> caller-owned) closure))
   #:description "Set the closure for SOURCE to CLOSURE."))

(define-class <gparam-spec-type> (<gobject-type-base>))

(define-method (unwrap-value-cg (type <gparam-spec-type>)
                                (value <gw-value>)
                                status-var)
  (let ((c-var (var value)) (scm-var (scm-var value)))
    (if-typespec-option
     value 'null-ok
     (list
      "if (SCM_FALSEP (" scm-var "))\n"
      "  " c-var " = NULL;\n")
     (list
      "if (!(" c-var " = scm_c_scm_to_gtype_instance_typed (" scm-var ", G_TYPE_PARAM)))\n"
      `(gw:error ,status-var type ,(wrapped-var value))))))


(define-method (wrap-value-cg (type <gparam-spec-type>)
                              (value <gw-value>)
                              status-var)
  (let ((c-var (var value)) (scm-var (scm-var value)))
    (list
     scm-var " = scm_c_gtype_instance_to_scm (" c-var ");\n")))

(define-class <gclosure-type> (<gobject-classed-pointer-type>))

(define-method (unwrap-value-cg (type <gclosure-type>)
                                (value <gw-value>)
                                status-var)
  (let ((c-var (var value)) (scm-var (scm-var value)))
    (list c-var " = scm_c_gvalue_peek_boxed (" scm-var ");\n")))

;; necessary gvalue functions:
;; peek_boxed
;; dup_boxed
;; new_boxed
;; new_take_boxed
;; peek_value
;; dup_value

(define-method (wrap-value-cg (type <gclosure-type>)
                              (value <gw-value>)
                              status-var)
  (let ((c-var (var value)) (scm-var (scm-var value))) ; not ideal but ok
    (list scm-var " = scm_c_gvalue_new_from_boxed (G_TYPE_CLOSURE, " c-var ");\n")))

(define-class <gvalue-type> (<gobject-type-base>))

(define-method (unwrap-value-cg (type <gvalue-type>)
                                (value <gw-value>)
                                status-var)
  (let ((c-var (var value)) (scm-var (scm-var value)))
    (list
     (if-typespec-option
      value 'callee-owned
      (list c-var " = scm_c_gvalue_dup_value (" scm-var ");\n")
      (list c-var " = scm_c_gvalue_peek_value (" scm-var ");\n")))))

(define-method (wrap-value-cg (type <gvalue-type>)
                              (value <gw-value>)
                              status-var)
  (let ((c-var (var value)) (scm-var (scm-var value)))
    (list
     "if (" c-var " != NULL)\n"
     (if-typespec-option
      value 'const
      (list scm-var " = scm_c_gvalue_from_value (" c-var ");\n")
      (list scm-var " = scm_c_gvalue_take_value (" c-var ");\n"))
     "else\n"
     "  " scm-var " = SCM_BOOL_F;\n")))
