/// Task - WASI 0.3 Task concept
///
/// A Task represents an export call boundary with associated state:
/// - Multiple threads (coroutines) can belong to one task
/// - Subtasks track import calls
/// - Backpressure control

/// Task state
pub(all) enum TaskState {
  Running
  Suspended  // Blocked on sync call to async component
  Completed
  Failed(Error)
}

/// Task ID
pub(all) struct TaskId(Int) derive(Eq, Hash, Show)

/// Subtask ID (for tracking import calls)
pub(all) struct SubtaskId(Int) derive(Eq, Hash, Show)

/// Task - represents an export call
pub struct Task {
  id : TaskId
  mut state : TaskState
  threads : Array[@coroutine.Coroutine]
  subtasks : Array[Subtask]
  mut backpressure : Bool
  parent : Task?  // Supertask
}

/// Subtask - represents an import call
pub struct Subtask {
  id : SubtaskId
  task : Task  // Parent task
  mut completed : Bool
}

/// Task registry - global task management
priv struct TaskRegistry {
  mut next_id : Int
  tasks : Map[TaskId, Task]
  mut current_task : Task?
}

/// Global task registry
let task_registry : TaskRegistry = {
  next_id: 1,
  tasks: {},
  current_task: None,
}

/// Create a new task (called when export is invoked)
pub fn Task::new(parent? : Task) -> Task {
  let id = TaskId(task_registry.next_id)
  task_registry.next_id += 1

  let task : Task = {
    id,
    state: Running,
    threads: [],
    subtasks: [],
    backpressure: false,
    parent,
  }

  task_registry.tasks.set(id, task)
  task
}

/// Get current task
pub fn Task::current() -> Task? {
  task_registry.current_task
}

/// Set current task (internal)
fn Task::set_current(task : Task?) -> Unit {
  task_registry.current_task = task
}

/// Run a function as a new task
pub async fn[T] Task::run(
  f : async () -> T,
  parent? : Task
) -> T raise Error {
  let task = Task::new(parent?)
  let prev_task = Task::current()
  Task::set_current(Some(task))

  // Add current coroutine to task
  task.threads.push(@coroutine.current_coroutine())

  try {
    let result = f()
    task.state = Completed
    Task::set_current(prev_task)
    result
  } catch {
    err => {
      task.state = Failed(err)
      Task::set_current(prev_task)
      raise err
    }
  }
}

/// Spawn a new thread within current task
pub fn Task::spawn_thread(f : async () -> Unit) -> @coroutine.Coroutine {
  let coro = @coroutine.spawn(f)
  match Task::current() {
    Some(task) => task.threads.push(coro)
    None => ()
  }
  coro
}

/// Spawn an async task (convenience wrapper)
pub fn spawn(f : async () -> Unit) -> Unit {
  let _ = @coroutine.spawn(f)
}

/// Create a subtask (called when import is invoked)
pub fn Task::create_subtask(self : Task) -> Subtask {
  let id = SubtaskId(task_registry.next_id)
  task_registry.next_id += 1

  let subtask : Subtask = {
    id,
    task: self,
    completed: false,
  }

  self.subtasks.push(subtask)
  subtask
}

/// Complete a subtask
pub fn Subtask::complete(self : Subtask) -> Unit {
  self.completed = true
}

/// Check if task is blocked (suspended)
pub fn Task::is_blocked(self : Task) -> Bool {
  self.state is Suspended
}

/// Check if task has backpressure active
pub fn Task::has_backpressure(self : Task) -> Bool {
  self.backpressure
}

/// Apply backpressure (stop accepting new async calls)
pub fn Task::apply_backpressure(self : Task) -> Unit {
  self.backpressure = true
}

/// Release backpressure
pub fn Task::release_backpressure(self : Task) -> Unit {
  self.backpressure = false
}

/// Get task ID
pub fn Task::id(self : Task) -> TaskId {
  self.id
}

/// Get task state
pub fn Task::get_state(self : Task) -> TaskState {
  self.state
}

/// Get parent task (supertask)
pub fn Task::parent(self : Task) -> Task? {
  self.parent
}

/// Get all threads in this task
pub fn Task::get_threads(self : Task) -> Array[@coroutine.Coroutine] {
  self.threads
}

/// Get pending subtasks
pub fn Task::pending_subtasks(self : Task) -> Array[Subtask] {
  self.subtasks.filter(fn(s) { not(s.completed) })
}

/// Check if all subtasks are complete
pub fn Task::all_subtasks_complete(self : Task) -> Bool {
  self.subtasks.iter().all(fn(s) { s.completed })
}
