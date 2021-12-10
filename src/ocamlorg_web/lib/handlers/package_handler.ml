type kind =
  | Package
  | Universe

let index _req =
  Page_layout_template.render
    ~title:"OCaml Packages · Browse community packages"
    ~description:
      "Discover thousands of community packages and their browse their \
       documentation."
    (Packages_template.render ())
  |> Dream.html

let search t req =
  match Dream.query "q" req with
  | Some search ->
    let packages = Ocamlorg_package.search_package t search in
    Page_layout_template.render
      ~title:"OCaml Packages · Search community packages"
      ~description:
        "Find the package you need to build your application in the thousands \
         of available opam packages."
      (Package_search_template.render packages)
    |> Dream.html
  | None ->
    Dream.redirect req "/packages"

let package t req =
  let package = Dream.param "name" req in
  let find_default_version name =
    Ocamlorg_package.get_package_latest t name
    |> Option.map (fun pkg -> Ocamlorg_package.version pkg)
  in
  let name = Ocamlorg_package.Name.of_string package in
  let version = find_default_version name in
  match version with
  | Some version ->
    let target =
      "/p/" ^ package ^ "/" ^ Ocamlorg_package.Version.to_string version
    in
    Dream.redirect req target
  | None ->
    Page_handler.not_found req

let package_versioned t kind req =
  let name = Ocamlorg_package.Name.of_string @@ Dream.param "name" req in
  let version =
    Ocamlorg_package.Version.of_string @@ Dream.param "version" req
  in
  let package = Ocamlorg_package.get_package t name version in
  match package with
  | None ->
    Page_handler.not_found req
  | Some package ->
    let open Lwt.Syntax in
    let kind =
      match kind with
      | Package ->
        `Package
      | Universe ->
        `Universe (Dream.param "hash" req)
    in
    let description =
      (Ocamlorg_package.info package).Ocamlorg_package.Info.description
    in
    let* readme =
      let+ readme_opt = Ocamlorg_package.readme_file ~kind package in
      Option.value
        readme_opt
        ~default:(description |> Omd.of_string |> Omd.to_html)
    in
    let license = Ocamlorg_package.license_file ~kind package in
    let* status = Ocamlorg_package.documentation_status ~kind package in
    let content = Package_template.render ~readme ~license package in
    let versions =
      Ocamlorg_package.get_package_versions t name |> Option.value ~default:[]
    in
    let toplevel = Ocamlorg_package.toplevel package in
    Package_layout_template.render
      ~title:
        (Printf.sprintf
           "%s %s · OCaml Packages"
           (Ocamlorg_package.Name.to_string name)
           (Ocamlorg_package.Version.to_string version))
      ~description:
        (Printf.sprintf
           "%s %s: %s"
           (Ocamlorg_package.Name.to_string name)
           (Ocamlorg_package.Version.to_string version)
           description)
      ~package
      ~versions
      ~tab:Overview
      ~status
      ?toplevel
      content
    |> Dream.html

let package_doc t kind req =
  let name = Ocamlorg_package.Name.of_string @@ Dream.param "name" req in
  let version =
    Ocamlorg_package.Version.of_string @@ Dream.param "version" req
  in
  let _kind =
    match kind with
    | Package ->
      Package_template.Blessed
    | Universe ->
      Package_template.Universe (Dream.param "hash" req)
  in
  let package = Ocamlorg_package.get_package t name version in
  match package with
  | None ->
    Page_handler.not_found req
  | Some package ->
    let open Lwt.Syntax in
    let kind =
      match kind with
      | Package ->
        `Package
      | Universe ->
        `Universe (Dream.param "hash" req)
    in
    let path = Dream.path req |> String.concat "/" in
    let root =
      let make =
        match kind with
        | `Package ->
          Fmt.str "/p/%s/%s/doc/"
        | `Universe u ->
          Fmt.str "/u/%s/%s/%s/doc/" u
      in
      make
        (Ocamlorg_package.Name.to_string name)
        (Ocamlorg_package.Version.to_string version)
    in
    let* docs = Ocamlorg_package.documentation_page ~kind package path in
    let* map = Ocamlorg_package.module_map ~kind package in
    let* status = Ocamlorg_package.documentation_status ~kind package in
    (match docs with
    | None ->
      Page_handler.not_found req
    | Some doc ->
      let description =
        (Ocamlorg_package.info package).Ocamlorg_package.Info.description
      in
      let versions =
        Ocamlorg_package.get_package_versions t name |> Option.value ~default:[]
      in
      let extra_nav = Package_doc_header_template.render doc.module_path in
      let canonical_module =
        doc.module_path
        |> List.map (function
               | Ocamlorg_package.Documentation.Module s ->
                 s
               | Ocamlorg_package.Documentation.ModuleType s ->
                 s
               | Ocamlorg_package.Documentation.FunctorArgument (_, s) ->
                 s)
        |> String.concat "."
      in
      let title =
        match path with
        | "index.html" ->
          Printf.sprintf
            "Documentation · %s %s · OCaml Packages"
            (Ocamlorg_package.Name.to_string name)
            (Ocamlorg_package.Version.to_string version)
        | _ ->
          Printf.sprintf
            "%s · %s %s · OCaml Packages"
            canonical_module
            (Ocamlorg_package.Name.to_string name)
            (Ocamlorg_package.Version.to_string version)
      in
      let toplevel = Ocamlorg_package.toplevel package in
      Package_layout_template.render
        ~title
        ~description:
          (Printf.sprintf
             "%s %s: %s"
             (Ocamlorg_package.Name.to_string name)
             (Ocamlorg_package.Version.to_string version)
             description)
        ~versions
        ~tab:Documentation
        ~status
        ~package
        ~extra_nav
        ?toplevel
        (Package_doc_template.render ~root map doc)
      |> Dream.html)

let package_toplevel t kind req =
  let name = Ocamlorg_package.Name.of_string @@ Dream.param "name" req in
  let version =
    Ocamlorg_package.Version.of_string @@ Dream.param "version" req
  in
  let package = Ocamlorg_package.get_package t name version in
  match package with
  | None ->
    Page_handler.not_found req
  | Some package ->
    let toplevel = Ocamlorg_package.toplevel package in
    (match toplevel with
    | None ->
      Page_handler.not_found req
    | Some toplevel ->
      let kind =
        match kind with
        | Package ->
          `Package
        | Universe ->
          `Universe (Dream.param "hash" req)
      in
      let open Lwt.Syntax in
      let* status = Ocamlorg_package.documentation_status ~kind package in
      let versions =
        Ocamlorg_package.get_package_versions t name |> Option.value ~default:[]
      in
      let content = Package_toplevel_template.render toplevel in
      let title =
        Printf.sprintf
          "Toplevel · %s %s · OCaml Packages"
          (Ocamlorg_package.Name.to_string name)
          (Ocamlorg_package.Version.to_string version)
      in
      let description =
        Printf.sprintf
          "%s %s: %s"
          (Ocamlorg_package.Name.to_string name)
          (Ocamlorg_package.Version.to_string version)
          (Ocamlorg_package.info package).Ocamlorg_package.Info.description
      in
      Package_layout_template.render
        ~title
        ~description
        ~package
        ~versions
        ~tab:Toplevel
        ~status
        ~toplevel
        content
      |> Dream.html)
