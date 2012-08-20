(in-package :coleslaw)

(defun app-path (path &rest args)
  "Take a relative PATH and return the corresponding pathname beneath coleslaw.
If ARGS is provided, use (apply 'format nil PATH ARGS) as the value of PATH."
  (merge-pathnames (apply 'format nil path args) coleslaw-conf:*basedir*))

(defun to-pathname (file parent)
  "Convert an iolib file-path back to a pathname."
  (merge-pathnames (file-path-namestring file) parent))

(defmacro do-files ((var path &optional extension) &body body)
  "For each file under PATH, run BODY. If EXTENSION is provided, only run BODY
on files that match the given extension."
  (alexandria:with-gensyms (ext)
    `(iolib.os:mapdir (lambda (x)
                        (let* ((,var (to-pathname x ,path))
                               ,@(when extension `((,ext (pathname-type ,var)))))
                          ,@(if extension
                                `((when (and ,ext (string= ,ext ,extension))
                                     ,@body))
                                `,body))) ,path)))

(defun compile-blog ()
  (let ((staging #p"/tmp/coleslaw/"))
    ; TODO: More incremental compilation? Don't regen whole blog unnecessarily.
    (if (probe-file staging)
        (delete-files staging :recursive t)
        (ensure-directories-exist staging))
    (with-current-directory staging
      (let ((css-dir (app-path "themes/~a/css/" (theme *config*)))
            (static-dir (merge-pathnames "static/" (repo *config*))))
        (dolist (dir (list css-dir static-dir))
          (run-program "cp" `("-R" ,dir "."))))
      (render-posts)
      (render-indices))
    (deploy staging)))

(defun render-page (path html)
  (ensure-directories-exist path)
  (with-open-file (out path
                   :direction :output
                   :if-does-not-exist :create)
    (let ((content (funcall (theme-fn "BASE")
                            (list :title (title *config*)
                                  :siteroot (domain *config*)
                                  :navigation (sitenav *config*)
                                  :content html
                                  :head-inject (apply #'concatenate 'string
                                                      (gethash :head *injections*))
                                  :body-inject (apply #'concatenate 'string
                                                      (gethash :body *injections*))
                                  :license (license *config*)
                                  :credits (author *config*)))))
      (write content out))))

(defun update-symlink (name target)
  "Update the symlink NAME to point to TARGET."
  (run-program "ln" (list "-sfn" (namestring target) name)))

(defun deploy (dir)
  "Deploy DIR, updating the .prev and .curr symlinks."
  (let ((new-build (app-path "generated/~a" (get-universal-time))))
    (run-program "mv" (list dir (namestring new-build)))
    (when (probe-file (app-path ".prev"))
      (delete-files (read-symlink (app-path ".prev")) :recursive t))
    (when (probe-file (app-path ".curr"))
      (update-symlink ".prev" (read-symlink (app-path ".curr"))))
    (update-symlink ".curr" new-build))
  (setf (last-published) (last-commit)))

(defun main ()
  (load-config)
  (compile-theme)
  (loop do (if (blog-update-p)
               (compile-blog)
               (sleep (interval *config*)))))
