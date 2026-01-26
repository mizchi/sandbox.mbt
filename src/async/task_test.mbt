test "task: create and state" {
  let task = @async.Task::new()
  assert_true(task.get_state() is @async.TaskState::Running)
  assert_false(task.has_backpressure())
}

test "task: backpressure on task" {
  let task = @async.Task::new()
  assert_false(task.has_backpressure())

  task.apply_backpressure()
  assert_true(task.has_backpressure())

  task.release_backpressure()
  assert_false(task.has_backpressure())
}

test "task: subtasks" {
  let task = @async.Task::new()
  assert_eq(task.pending_subtasks().length(), 0)

  let subtask = task.create_subtask()
  assert_eq(task.pending_subtasks().length(), 1)

  subtask.complete()
  assert_eq(task.pending_subtasks().length(), 0)
  assert_true(task.all_subtasks_complete())
}

test "task: parent relationship" {
  let parent = @async.Task::new()
  let child = @async.Task::new(parent=parent)

  assert_true(child.parent() is Some(_))
}
