(in-package :cl-user)
(defpackage qlot.source.git
  (:use :cl
        :qlot.source)
  (:import-from :qlot.tmp
                :tmp-path)
  (:import-from :qlot.archive
                :create-tarball)
  (:import-from :qlot.shell
                :safety-shell-command
                :shell-command-error)
  (:export :source-git
           :retry-git-clone))
(in-package :qlot.source.git)

(defclass source-git (source-has-directory)
  ((repos-url :initarg :repos-url
              :accessor source-git-repos-url)
   (ref :initarg :ref
        :initform nil
        :accessor source-git-ref)
   (branch :initarg :branch
           :initform nil
           :accessor source-git-branch)
   (tag :initarg :tag
        :initform nil
        :accessor source-git-tag)))

(defmethod make-source ((source (eql 'source-git)) &rest args)
  (destructuring-bind (project-name repos-url &rest args) args
    (apply #'make-instance 'source-git
           :project-name project-name
           :repos-url repos-url
           args)))

(defmethod initialize ((source source-git))
  (setf (source-directory source)
        (pathname
         (format nil "~A~:[~;~:*-~A~]/"
                 (source-project-name source)
                 (source-git-identifier source))))
  (unless (probe-file (source-directory source))
    (git-clone source))
  (setf (source-version source)
        (retrieve-source-git-ref source))
  (setf (source-archive source)
        (pathname
         (format nil "~A-~A.tar.gz"
                 (source-project-name source)
                 (source-version source))))

  (create-tarball (source-directory source)
                  (source-archive source)))

(defmethod print-object ((source source-git) stream)
  (format stream "#<~S ~A ~A~:[~;~:* ~A~]>"
          (type-of source)
          (source-project-name source)
          (source-git-repos-url source)
          (source-git-identifier source)))

(defun source-git-identifier (source)
  (cond
    ((source-git-ref source)
     (concatenate 'string "ref-" (source-git-ref source)))
    ((source-git-branch source)
     (concatenate 'string "branch-" (source-git-branch source)))
    ((source-git-tag source)
     (concatenate 'string "tag-" (source-git-tag source)))))

(defmethod retrieve-source-git-ref ((source source-git))
  (labels ((show-ref (pattern)
             (handler-case
                 (ppcre:scan-to-strings "^\\S+"
                                        (safety-shell-command "git"
                                                              (list "--git-dir"
                                                                    (format nil "~A.git"
                                                                            (source-directory source))
                                                                    "show-ref"
                                                                    pattern)))
               (shell-command-error ()
                 (error "No git references named '~A'." pattern))))
           (get-ref (source)
             (cond
               ((source-git-ref source))
               ((source-git-branch source)
                (show-ref (format nil "refs/heads/~A" (source-git-branch source))))
               ((source-git-tag source)
                (show-ref (format nil "refs/tags/~A" (source-git-tag source))))
               (T (show-ref "HEAD")))))
    (format nil "git-~A" (get-ref source))))

(defun git-clone (source)
  (check-type source source-git)
  (let ((dir (source-directory source))
        (checkout-to (or (source-git-ref source)
                         (source-git-branch source)
                         (source-git-tag source))))
    (tagbody git-cloning
       (restart-case
           (safety-shell-command "git"
                                 (list "clone"
                                       (source-git-repos-url source)
                                       dir))
         (retry-git-clone ()
           :report "Retry to git clone the repository."
           (when (probe-file dir)
             (fad:delete-directory-and-files dir))
           (go git-cloning))))
    (when checkout-to
      (safety-shell-command "git"
                            (list "--git-dir"
                                  (format nil "~A.git" dir)
                                  "--work-tree"
                                  dir
                                  "checkout"
                                  checkout-to)))))
