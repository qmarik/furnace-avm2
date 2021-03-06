module Furnace::AVM2
  module Transform
    class ASTNormalize
      include AST::Visitor

      def initialize(options={})
        @options = options
      end

      def transform(ast, *stuff)
        visit ast

        [ ast, *stuff ]
      end

      # (pop x) -> (jump-target) x
      def on_pop(node)
        child = node.children.first

        node.update(:expand, [
          child,
          AST::Node.new(:nop, [], node.metadata)
        ], nil)
      end

      # (call-property-void *) -> (call-property *)
      def on_call_property_void(node)
        node.update(:call_property)
      end

      # (call-super-void *) -> (call-super *)
      def on_call_super_void(node)
        node.update(:call_super)
      end

      # (if-* a b) -> (*' a b)
      IF_MAPPING = {
        :eq        => [false, :==],
        :ne        => [false, :!=],
        :ge        => [false, :>=],
        :nge       => [true,  :>=],
        :gt        => [false, :>],
        :ngt       => [true,  :>],
        :le        => [false, :<=],
        :nle       => [true,  :<=],
        :lt        => [false, :<],
        :nlt       => [true,  :<],
        :strict_eq => [false, :===],
        :strict_ne => [true,  :===], # Why? Because of (lookup-switch ...).
        :true      => [false, :expand],
        :false     => [true,  :expand]
      }

      def transform_conditional(node, comp, reverse)
        node.update(comp)
        node.parent.children[0] = !node.parent.children[0] if reverse
      end

      IF_MAPPING.each do |cond, (reverse, comp)|
        define_method :"on_if_#{cond}" do |node|
          if node.parent.type == :jump_if || comp != :expand
            # Parent is a conditional, or this is an explicit comparsion.
            transform_conditional(node, comp, reverse)
          elsif node.parent.type == :ternary_if && node.index == 1
            # Parent is a comparsion-less ternary operator, and this
            # node is in condition position.
            transform_conditional(node, comp, reverse)
            node.parent.update(:ternary_if_boolean)
          elsif node.children.count == 2
            # This is an implicit comparsion, and it is not located in
            # a condition position of a conditional or a ternary operator.
            # Turn it into a ternary operator as of itself.
            node.update(:ternary_if_boolean, [
              !comp, *node.children
            ])
            on_ternary_if_boolean(node)
          else
            transform_conditional(node, comp, reverse)
          end
        end
      end

      # (ternary-if * (op a b x y)) -> (ternary-if-boolean * (op a b) x y)
      def on_ternary_if(node)
        comparsion, op = node.children
        node.children.concat op.children.slice!(2..-1)

        on_ternary_if_boolean(node)
      end

      # (ternary-if-boolean true  (op a b) x y) -> (ternary (op a b) x y)
      # (ternary-if-boolean false (op a b) x y) -> (ternary (op a b) y x)
      def on_ternary_if_boolean(node)
        comparsion, condition, if_true, if_false = node.children
        if comparsion
          node.update(:ternary, [ condition, if_true, if_false ])
        else
          node.update(:ternary, [ condition, if_false, if_true ])
        end
      end

      # (&& (coerce-b ...) (coerce-b ...)) -> (&& ... ...)
      def fix_boolean(node)
        node.children.map! do |child|
          if child.is_a?(AST::Node) &&
                child.type == :coerce_b
            child.children.first
          else
            child
          end
        end
      end
      alias :on_and     :fix_boolean
      alias :on_or      :fix_boolean
      alias :on_jump_if :fix_boolean

      def replace_with_nop(node)
        node.update(:nop)
      end
      alias :on_kill        :replace_with_nop
      alias :on_debug       :replace_with_nop
      alias :on_debug_file  :replace_with_nop
      alias :on_debug_line  :replace_with_nop
    end
  end
end