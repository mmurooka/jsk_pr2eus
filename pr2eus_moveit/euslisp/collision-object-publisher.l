(ros::load-ros-manifest "moveit_msgs")

(defclass collision-object-publisher
  :super propertied-object
  :slots (object-list topicname scenetopic))

(defmethod collision-object-publisher
  (:init (&key (topic-name "collision_object") (scene-topic "get_planning_scene"))
   (unless (ros::ok) (ros::roseus "publish_collision_eusobj"))
   (setq topicname topic-name
         scenetopic scene-topic)
   (ros::advertise topicname moveit_msgs::CollisionObject 100)
   (setq object-list (make-hash-table)))
  (:add-object
   (obj &key (frame_id "base_footprint")) ;;
   (let ((msg (gethash obj object-list)))
     (when msg (return-from :add-object)))
   (let* ((id (symbol-string (gensym "COLOBJ")))
          (colobj (instance moveit_msgs::CollisionObject :init :id id))
          geom-lst pose-lst)

     (send colobj :operation moveit_msgs::CollisionObject::*ADD*)

     (send colobj :header :frame_id frame_id)
     (send colobj :header :stamp (ros::time-now))

     (cond
      ((and (derivedp obj body) (eq (car (send obj :body-type)) :cylinder))
       (let ((geom (send colobj :primitives))
             (pose (send colobj :primitive_poses)))
         (send colobj :primitives
               (append geom
                       (list
                        (instance shape_msgs::SolidPrimitive
                                  :init :type shape_msgs::SolidPrimitive::*CYLINDER*
                                  :dimensions (float-vector
                                               (/ (radius-of-cylinder obj) 1000.0)
                                               (/ (height-of-cylinder obj) 1000.0))))))
         (send colobj :primitive_poses
               (append pose
                       (list
                        (ros::coords->tf-pose (send obj :worldcoords)))))))
      ((and (derivedp obj body) (eq (car (send obj :body-type)) :cube))
       (let ((geom (send colobj :primitives))
             (pose (send colobj :primitive_poses)))
         (send colobj :primitives
               (append geom
                       (list
                        (instance shape_msgs::SolidPrimitive
                                  :init :type shape_msgs::SolidPrimitive::*BOX*
                                  :dimensions (float-vector
                                               (/ (elt (send obj :body-type) 1) 1000.0)
                                               (/ (elt (send obj :body-type) 2) 1000.0)
                                               (/ (elt (send obj :body-type) 3) 1000.0))))))
         (send colobj :primitive_poses
               (append pose
                       (list
                        (ros::coords->tf-pose (send obj :worldcoords)))))))
      ((and (derivedp obj body) (eq (car (send obj :body-type)) :gdome))
       (let ((geom (send colobj :primitives))
             (pose (send colobj :primitive_poses)))
         (send colobj :primitives
               (append geom
                       (list
                        (instance shape_msgs::SolidPrimitive
                                  :init :type shape_msgs::SolidPrimitive::*SPHERE*
                                  :dimensions (float-vector
                                               (/ (radius-of-sphere obj) 1000.0))))))
         (send colobj :primitive_poses
               (append pose
                       (list
                        (ros::coords->tf-pose (send obj :worldcoords)))))))
      ((find-method obj :faces)
       (let ((org-cds (send obj :copy-worldcoords)))
         (send obj :reset-coords)
         (send obj :worldcoords)
         (let ((fs (body-to-faces obj))
               (geom (instance shape_msgs::mesh :init))
               idx-lst vertices (cntr 0))
           (dolist (f (send fs :faces))
             (let* ((vs (send f :vertices))
                    (v0 (car vs))
                    (v1 (cadr vs))
                    (v2 (caddr vs))
                    (p0
                     (instance geometry_msgs::Point :init
                               :x (/ (elt v0 0) 1000.0)
                               :y (/ (elt v0 1) 1000.0)
                               :z (/ (elt v0 2) 1000.0)))
                    (p1
                     (instance geometry_msgs::Point :init
                               :x (/ (elt v1 0) 1000.0)
                               :y (/ (elt v1 1) 1000.0)
                               :z (/ (elt v1 2) 1000.0)))
                    (p2
                     (instance geometry_msgs::Point :init
                               :x (/ (elt v2 0) 1000.0)
                               :y (/ (elt v2 1) 1000.0)
                               :z (/ (elt v2 2) 1000.0))))
               (push p0 vertices)
               (push p1 vertices)
               (push p2 vertices)
               (push (integer-vector cntr (+ cntr 1) (+ cntr 2)) idx-lst)
               (incf cntr 3)
               ))
           (send geom :triangles
                 (mapcar #'(lambda (idx)
                             (instance shape_msgs::MeshTriangle :init :vertix_indices idx))
                         (nreverse idx-lst)))
           (send geom :vertices (nreverse vertices))
           (let ((m (send colobj :meshes))
                 (mp (send colobj :meshes_poses)))
             (send colobj :meshes (append m (list geom)))
             (send colobj :meshes (append mp (list (ros::coords->tf-pose (send obj :worldcoords))))))
           )
         (send obj :transform org-cds)
         (send obj :worldcoords)))
      ((derivedp obj pointcloud)
       ;; making voxel grid ...
       )
      ((find-method obj :vertices)
       ;; making bounding box
       ;; (send obj :vertices)
       )
      (t
       (warn ";; not supported object type~%")
       (return-from :add-object)
       ))

     (setf (gethash obj object-list) colobj)
     (ros::publish topicname colobj)
     obj))
  (:clear-all ()
   (dolist (obj (send object-list :list-keys))
     (send self :delete-object obj))
   (setq object-list (make-hash-table))
   t)
  (:wipe-all ()
   (let ((scene (get-planning-scene :scene-topic scenetopic
                                    :components (+ moveit_msgs::PlanningSceneComponents::*WORLD_OBJECT_NAMES*
                                                   moveit_msgs::PlanningSceneComponents::*WORLD_OBJECT_GEOMETRY*
                                                   moveit_msgs::PlanningSceneComponents::*OCTOMAP*))))
     (when scene
       (dolist (msg (send scene :world :collision_objects))
         (send msg :header :stamp (ros::time-now))
         (send msg :operation :operation moveit_msgs::CollisionObject::*REMOVE*)
         (ros::publish topicname msg))
       (setq object-list (make-hash-table))
       t)))
  (:delete-object (obj)
   (let ((msg (gethash obj object-list)))
     (unless msg (return-from :delete-object))
     (send msg :header :stamp (ros::time-now))
     (send msg :operation moveit_msgs::CollisionObject::*REMOVE*)
     (remhash obj object-list)
     (ros::publish topicname msg)
     obj))
  )

(defun get-planning-scene (&key (scene-topic "get_planning_scene")
                                (components 1023))
  ;;moveit_msgs::PlanningSceneComponents::*SCENE_SETTINGS*
  ;;moveit_msgs::PlanningSceneComponents::*ROBOT_STATE*
  ;;moveit_msgs::PlanningSceneComponents::*ROBOT_STATE_ATTACHED_OBJECTS*
  ;;moveit_msgs::PlanningSceneComponents::*WORLD_OBJECT_NAMES*
  ;;moveit_msgs::PlanningSceneComponents::*WORLD_OBJECT_GEOMETRY*
  ;;moveit_msgs::PlanningSceneComponents::*OCTOMAP*
  ;;moveit_msgs::PlanningSceneComponents::*TRANSFORMS*
  ;;moveit_msgs::PlanningSceneComponents::*ALLOWED_COLLISION_MATRIX*
  ;;moveit_msgs::PlanningSceneComponents::*LINK_PADDING_AND_SCALING*
  ;;moveit_msgs::PlanningSceneComponents::*OBJECT_COLORS*
  (let ((req (instance moveit_msgs::GetPlanningSceneRequest :init))
        ret)
    (send req :components :components components)
    (setq ret (ros::service-call scene-topic req))
    (if ret (send ret :scene))
    ))

(defun make-collision-map (vox-center-3dp-lst &key (stamp (ros::time-now))
                                              (frame "base_footprint") (grid-size 30))
  (let* ((hd (instance std_msgs::header :init :frame_id frame :stamp stamp))
         (cmap (instance moveit_msgs::CollisionMap :init :header hd))
         lst (meter-grid-size (* (/ grid-size 2) 0.001)))
    ;;
    (dolist (p vox-center-3dp-lst)
      (let ((bx
             (instance moveit_msgs::OrientedBoundingBox :init)))
        (send bx :pose :position :x (* 0.001 (elt p 0)))
        (send bx :pose :position :y (* 0.001 (elt p 1)))
        (send bx :pose :position :z (* 0.001 (elt p 2)))
        (send bx :pose :orientation :w 1)
        (send bx :extents :x meter-grid-size)
        (send bx :extents :y meter-grid-size)
        (send bx :extents :z meter-grid-size)
        (push bx lst)))
    (send cmap :boxes (nreverse lst))
    cmap))