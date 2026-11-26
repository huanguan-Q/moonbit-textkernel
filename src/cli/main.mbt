// Native CLI: same commands as the wasm/moonx entry point, plus stdin.
// File input is the shell's job: `textkernel escape-html < input.txt`.

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    println(@lib.cli_help())
    return
  }

  let command = args[1]
  if command == "--help" || command == "help" {
    println(@lib.cli_help())
    return
  }

  let mut input : String? = None
  let mut hosts_csv = ""
  let mut params_csv = ""
  let mut i = 2
  while i < args.length() {
    let arg = args[i]
    if arg == "--input" || arg == "--hosts" || arg == "--params" {
      if i + 1 >= args.length() {
        println(@lib.cli_json_error(command, "missing value for " + arg))
        @env.exit(@lib.CLI_USAGE_EXIT)
      }
      let value = args[i + 1]
      if arg == "--input" {
        input = Some(value)
      } else if arg == "--hosts" {
        hosts_csv = value
      } else {
        params_csv = value
      }
      i = i + 2
    } else {
      input = Some(arg)
      i = i + 1
    }
  }

  let text = match input {
    Some(value) => value
    None => @stdio.stdin.text.read_all()
  }
  let config = @lib.cli_config(hosts_csv, params_csv)
  match @lib.run_cli(command, text, config) {
    Ok(output) => println(@lib.cli_json_line(command, output))
    Err(message) => {
      println(@lib.cli_json_error(command, message))
      @env.exit(@lib.CLI_USAGE_EXIT)
    }
  }
}
