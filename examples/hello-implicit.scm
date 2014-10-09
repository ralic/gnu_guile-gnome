#! /bin/sh
# -*- scheme -*-
exec guile -e main -s $0 "$@"
!#
;; guile-gnome
;; Copyright (C) 2008, 2012 Free Software Foundation, Inc.

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


(use-modules (gnome-2)
             (srfi srfi-11)
             (oop goops)
             (gnome gobject)
             (gnome glib)
             (gnome clutter))

(define *loop* (g-main-loop-new))
(define *stage* #f)
(define *color* '(#xff #xcc #xcc #xdd))

(define (on-button-press stage event)
  (pk 'button-pressed! stage event)
  #t)

(define (prep-stage)
  (set! *stage* (clutter-stage-new))
  (set-background-color *stage* (pk (clutter-color-from-string "DarkSlateGrey")))
  (set-size *stage* 800 600)
  (set-title *stage* "My First Clutter Application")
  (connect *stage* 'key-press-event
           (lambda (s e) (g-main-loop-quit *loop*) #t))
  (connect *stage* 'button-press-event on-button-press))

(define (fold-pack w h . procs)
  (pk w h procs)
  (if (pair? procs)
      (let-values (((w h) ((car procs) w h)))
        (apply fold-pack w h (cdr procs)))))

(define (show-message msg)
  (define (make-label sw sh)
    (let ((l (make <clutter-text>
               #:font-name "Mono 22" #:text msg #:color *color*)))
      (let-values (((w h) (get-size l)))
        (pk w h)
        (set-position l (- sw w 50) (- sh h))
        (add-child *stage* l)
        (values sw (- sh h)))))

  (define (make-cursor sw sh)
    (let* ((c (make <clutter-actor>
                #:background-color *color* #:width 20 #:height (pk (- (get-height *stage*) sh))
                #:x (- sw 50) #:y sh #:opacity #xdd)))
      (save-easing-state c)
      (set-easing-duration c 800) ; milliseconds
      (set-opacity c 0)
      (set-repeat-count (get-transition c "opacity") -1)
      (restore-easing-state c)
      (add-child *stage* c)
      (values sw sh)))

  (fold-pack (get-width *stage*) (get-height *stage*)
             make-label
             make-cursor))

(define (main args)
  (let ((message (if (pair? (cdr args)) (cadr args) "Hello from Guile-Clutter!")))
    (prep-stage)
    (show-message message)
    (show *stage*)
    (g-main-loop-run *loop*)
    (exit 0)))