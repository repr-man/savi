##
# WIP: This pass is intended to be a future replacement for the Infer pass,
# but it is still a work in progress and isn't in the main compile path yet.
#
module Savi::Compiler::Types
  struct Analysis
    @scope : TypeVariable::Scope

    def initialize(@scope)
      @constraint_summaries = {} of TypeVariable => AlgebraicType
      @assignment_summaries = {} of TypeVariable => AlgebraicType
      @resolved = {} of TypeVariable => AlgebraicType
    end

    def [](var)
      @resolved[var]
    end
    def []?(var)
      @resolved[var]?
    end

    protected def set_resolved(var, type)
      @resolved[var] = type
    end

    def calculate_constraint_summary(var)
      @resolved[var]? || begin
        @constraint_summaries[var] ||= begin
          raise "wrong scope" if var.scope != @scope
          yield
        end
      end
    end

    def calculate_assignment_summary(var)
      @resolved[var]? || begin
        @assignment_summaries[var] ||= begin
          raise "wrong scope" if var.scope != @scope
          yield
        end
      end
    end
  end

  struct Cursor
    @ctx : Context
    @pass : Pass
    property! current_pos : Source::Pos

    def initialize(@ctx, @pass)
      @reached_scopes = Set(TypeVariable::Scope).new
      @reached = Set(TypeVariable).new
      @facts = [] of {Source::Pos, AlgebraicType}
    end

    def start
      @current_pos = nil
      @reached_scopes.clear
      @reached.clear
      @facts.clear
      self
    end

    def reach(var)
      return if @reached.includes?(var)
      @reached_scopes.add(var.scope)
      @reached.add(var)
      yield
    end

    def add_fact(pos, type)
      @facts << {pos, type}
    end

    def add_fact_at_current_pos(type)
      @facts << {current_pos, type}
    end

    def each_fact
      @facts.each { |pos, type| yield ({pos, type}) }
    end

    private def current_facts_offset
      @facts.size
    end

    private def transform_facts_since(offset)
      @facts.map_with_index!(offset) { |fact, index|
        (yield fact).as({Source::Pos, AlgebraicType})
      }
    end

    def trace_as_assignment_with_transform(type)
      pre_offset = current_facts_offset
      type.trace_as_assignment(self)
      transform_facts_since(pre_offset) { |pos, inner|
        {pos, yield inner}
      }
    end

    def trace_call_return_as_assignment(
      pos : Source::Pos,
      call : AST::Call,
      receiver : AlgebraicType,
    )
      @current_pos = pos
      offset = current_facts_offset
      receiver.trace_call_return_as_assignment(self, call)
    end

    def trace_call_return_as_assignment(
      call : AST::Call,
      nominal_type : NominalType,
      nominal_cap : NominalCap,
    )
      raise NotImplementedError.new(nominal_type.show) if nominal_type.args

      @pass.trace_call_return_as_assignment(
        @ctx, self, nominal_type.link, call.ident
      )
    end
  end

  class Pass
    def initialize
      @f_analyses = {} of Program::Function::Link => Analysis
    end

    def [](f_link : Program::Function::Link)
      @f_analyses[f_link]
    end
    def []?(f_link : Program::Function::Link)
      @f_analyses[f_link]?
    end

    def run(ctx : Context)
      run_for_types(ctx)
      run_for_func_edges(ctx)
    end

    def run_for_types(ctx : Context)
      cursor = Cursor.new(ctx, self)

      ctx.program.libraries.each { |l|
        l_link = l.make_link
        l.types.each { |t|
          t_link = t.make_link(l_link)
          types_graph = ctx.types_graph[t_link]
          analysis = Analysis.new(t_link)

          types_graph.field_type_vars.each { |name, var|
            resolved = var.calculate_assignment_summary(analysis, cursor.start)
            analysis.set_resolved(var, resolved)
          }
        }
      }
    end

    def run_for_func_edges(ctx : Context)
      cursor = Cursor.new(ctx, self)

      ctx.program.libraries[2].tap { |l| # TODO: all libraries
        l_link = l.make_link
        l.types.each { |t|
          t_link = t.make_link(l_link)
          t.functions.each { |f|
            f_link = f.make_link(t_link)
            types_graph = ctx.types_graph[f_link]
            analysis = @f_analyses[f_link] = Analysis.new(f_link)

            types_graph.return_var.tap { |var|
              resolved = var.calculate_assignment_summary(analysis, cursor.start)
              analysis.set_resolved(var, resolved)
            }
          }
        }
      }
    end

    def trace_call_return_as_assignment(ctx, cursor, t_link, f_ident)
      t = t_link.resolve(ctx)
      f = t.find_func?(f_ident.value)
      raise "function not found" unless f # TODO: nice error
      f_link = f.make_link(t_link)
      types_graph = ctx.types_graph[f_link]
      types_graph.return_var.trace_as_assignment(cursor)
    end
  end
end
