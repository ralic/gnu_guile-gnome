#!/bin/sh
# -*- scheme -*-
exec guile --debug -s $0 "$@"
!#

;; guile-gnome
;; Copyright (C) 2006 Free Software Foundation
;; Copyright (C) 2007 Andy Wingo <wingo at pobox dot com>

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

;; All of the parsing code was written by Ludovic Courtès.

(use-modules (texinfo)
             (texinfo reflection)
             (texinfo serialize)

             (ice-9 rdelim)

             ((srfi srfi-1) #:select (append-map))
             (srfi srfi-13)
             (srfi srfi-14))

(define (snarf-line? line)
  "Return true if @var{line} (a string) can be considered a line produced by
the @code{snarf.h} snarfing macros."
  (and (>= (string-length line) 4)
       (string=? (substring line 0 4) "^^ {")))

(define (parse-c-argument-list arg-string)
  "Parse @var{arg-string} (a string representing a ANSI C argument list,
e.g., @var{(const SCM first, SCM second_arg)}) and return a list of strings
denoting the argument names."
  (define %c-symbol-char-set
    (char-set-adjoin char-set:letter+digit #\_))

  (let loop ((args (string-tokenize (string-trim-both arg-string #\space)
                                    %c-symbol-char-set))
             (type? #t)
             (result '()))
    (if (null? args)
        (reverse! result)
        (let ((the-arg (car args)))
          (cond ((and type? (string=? the-arg "const"))
                 (loop (cdr args) type? result))
                ((and type? (string=? the-arg "SCM"))
                 (loop (cdr args) (not type?) result))
                (type? ;; any other type, e.g., `void'
                 (loop (cdr args) (not type?) result))
                (else
                 (loop (cdr args) (not type?) (cons the-arg result))))))))

(define (parse-documentation-item item)
  "Parse @var{item} (a string), a single function string produced by the C
preprocessor.  The result is an alist whose keys represent specific aspects
of a procedure's documentation: @code{c-name}, @code{scheme-name},
 @code{documentation} (a Texinfo documentation string), etc."

  (define (read-strings)
    ;; Read several subsequent strings and return their concatenation.
    (let loop ((str (read))
               (result '()))
      (if (or (eof-object? str)
              (not (string? str)))
          (string-concatenate (reverse! result))
          (loop (read) (cons str result)))))

  ;;(format (current-error-port) "doc-item: ~a~%" item)
  (let* ((item (string-trim-both item #\space))
         (space (or (string-index item #\space) 0)))
    (let ((kind (substring item 0 space))
          (rest (substring item space (string-length item))))
      (cond ((string=? kind "cname")
             (cons 'c-name (string-trim-both rest #\space)))
            ((string=? kind "fname")
             (cons 'scheme-name
                   (with-input-from-string rest read-strings)))
            ((string=? kind "type")
             (cons 'type (with-input-from-string rest read)))
            ((string=? kind "location")
             (cons 'location
                   (with-input-from-string rest
                     (lambda ()
                       (let loop ((str (read))
                                  (result '()))
                         (if (eof-object? str)
                             (reverse! result)
                             (loop (read) (cons str result))))))))
            ((string=? kind "arglist")
             (cons 'arguments
                   (parse-c-argument-list rest)))
            ((string=? kind "argsig")
             (cons 'signature
                   (with-input-from-string rest
                     (lambda ()
                       (let ((req (read)) (opt (read)) (rst? (read)))
                         (list (cons 'required req)
                               (cons 'optional opt)
                               (cons 'rest?    (= 1 rst?))))))))
            (else
             ;; docstring (may consist of several C strings which we
             ;; assume to be equivalent to Scheme strings)
             (cons 'documentation
                   (with-input-from-string item read-strings)))))))

(define (parse-snarfed-line line)
  "Parse @var{line}, a string that contains documentation returned for a
single function by the C preprocessor with the @code{-DSCM_MAGIC_SNARF_DOCS}
option.  @var{line} is assumed to obey the @code{snarf-line?} predicate."
  (define (caret-split str)
    (let loop ((str str)
               (result '()))
      (if (string=? str "")
          (reverse! result)
          (let ((caret (string-index str #\^))
                (len (string-length str)))
            (if caret
                (if (and (> (- len caret) 0)
                         (eq? (string-ref str (+ caret 1)) #\^))
                    (loop (substring str (+ 2 caret) len)
                          (cons (string-take str (- caret 1)) result))
                    (error "single caret not allowed" str))
                (loop "" (cons str result)))))))

  (let ((items (caret-split (substring line 4
                                       (- (string-length line) 4)))))
    (map parse-documentation-item items)))


(define (parse-snarfing port)
  "Read C preprocessor (where the @code{SCM_MAGIC_SNARF_DOCS} macro is
defined) output from @var{port} a return a list of alist, each of which
contains information about a specific function described in the C
preprocessor output."
  (let loop ((line (read-line port))
             (result '()))
    ;;(format (current-error-port) "line: ~a~%" line)
    (if (eof-object? line)
        result
        (cond ((snarf-line? line)
               (loop (read-line port)
                     (cons (parse-snarfed-line line) result)))
              (else
               (loop (read-line port) result))))))

(define (list-intersperse src-l elem)
  (if (null? src-l) src-l
      (let loop ((l (cdr src-l)) (dest (cons (car src-l) '())))
        (if (null? l) (reverse dest)
            (loop (cdr l) (cons (car l) (cons elem dest)))))))

(define (snarfing->stexi alist)
  `(deffn (% (name ,(assq-ref alist 'scheme-name))
             (category "Primitive") ;; ,(assq-ref alist 'type))
             (arguments ,@(list-intersperse (assq-ref alist 'arguments) " ")))
     ,@(cdr (texi-fragment->stexi (assq-ref alist 'documentation)))))

(define (parse-c-docs dot-doc-files)
  (append-map
   (lambda (filename)
     (call-with-input-file filename
       (lambda (port)
         (map snarfing->stexi (parse-snarfing port)))))
   dot-doc-files))

(define (def-name def)
  (string->symbol (cadr (assq 'name (cdadr def)))))

(define (main config-scm . dot-doc-files)
  (define docs-resolver
    (let* ((defs (parse-c-docs dot-doc-files))
           (defs-alist (map cons (map def-name defs) defs)))
      (lambda (name def)
        (or (and=> (assq name defs-alist) cdr)
            def))))
  (primitive-load config-scm)
  (display
   (stexi->texi
    (package-stexi-documentation
     (map car *modules*)
     *name*
     (string-append *texinfo-basename* ".info")
     (package-stexi-standard-prologue
      *name*
      (string-append *texinfo-basename* ".info")
      *texinfo-category*
      *description*
      (package-stexi-standard-copying
       *name* *version* *updated* *years* *copyright-holder* *permissions*)
      (package-stexi-standard-titlepage
       *name* *version* *updated* *authors*)
      (package-stexi-standard-menu
       *name* (map car *modules*) (map cdr *modules*)
       *extra-texinfo-menu-entries*))
     *texinfo-epilogue*
     #:module-stexi-documentation-args (list #:docs-resolver
                                             docs-resolver)))))

(apply main (cdr (command-line)))
