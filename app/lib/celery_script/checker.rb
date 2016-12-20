module CeleryScript
  class TypeCheckError < StandardError; end
  class Checker
    MISSING_ARG = "Expected node '%s' to have a '%s', but got: %s."
    EXTRA_ARGS  = "'%s' has unexpected arguments: %s. Allowed arguments: %s"
    BAD_LEAF    = "Expected leaf '%s' within '%s' to be one of: %s but got %s"
    MALFORMED   = "Expected '%s' to be a node or leaf, but it was neither"
    BAD_BODY    = "Body of '%s' node contains '%s' node. "\
                  "Expected one of: %s"

    attr_reader :tree, :corpus

    def initialize(tree, corpus)
      @tree, @corpus = tree, corpus
      self.freeze
    end

    def run!
      cb = method(:validate)
      CeleryScript::TreeClimber.travel(tree, cb.to_proc)
      tree
    end

    def run
      error || tree
    end

    def valid?
      error ? false : true
    end

    def error
      run!
      nil
    rescue TypeCheckError => e
      e
    end

    private

    def validate(node)
      validate_body(node)
      validate_node(node)
    end

    def validate_body(node)
      (node.body || []).each_with_index do |inner_node, i|
        allowed = corpus.fetchNode(node.kind).allowed_body_types
        body_ok = Array(allowed)
                    .map(&:to_sym)
                    .include?(inner_node.kind.to_sym)
        bad_body_kind(node, inner_node, i, allowed) unless body_ok
      end
    end

    def validate_node(node)
      check_arity(node)
      node.args.map do |array|
        should_be = array.first
        node      = array.last
        check_arg_validity(should_be, node)
      end
    end

    def check_arity(node)
        allowed = corpus
        .fetchNode(node.kind)
        .allowed_args
        allowed.map do |arg|
          has_key = node.args.has_key?(arg) || node.args.has_key?(arg.to_s)
          unless has_key
            msgs = node.args.keys.join(", ")
            msgs = "nothing" if msgs.length < 1
          msg = MISSING_ARG % [node.kind, arg, msgs]
          raise TypeCheckError, msg
          end
        end
      has      = node.args.keys.map(&:to_sym) # Either bigger or equal.
      required = corpus.fetchNode(node.kind).allowed_args # Always smallest.
      if !(has.length === required.length)
        extras = has - required
        raise TypeCheckError, (EXTRA_ARGS % [node.kind, extras, allowed])
      end
    end

    def check_arg_validity(should_be, node)
      case node
      when AstNode
      when AstLeaf
        allowed = corpus
                    .fetchArg(node.kind)
                    .allowed_values
                    .select { |d| d.is_a?(Class) }
        actual = node.value.class
        unless allowed.include?(actual)
          raise TypeCheckError, (BAD_LEAF % [node.kind, node.parent.kind,
                                             allowed.inspect, actual.inspect])
        end
      else
        raise TypeCheckError, (MALFORMED % should_be)
      end
      validator = corpus.fetchArg(should_be).additional_validation
      validator.call(node, TypeCheckError, corpus) if(validator)
    end

    def bad_body_kind(prnt, child, i, ok)
      raise TypeCheckError, (BAD_BODY % [prnt.kind, child.kind, ok.inspect])
    end
  end
end