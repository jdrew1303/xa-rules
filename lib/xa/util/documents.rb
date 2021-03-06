module XA
  module Util
    module Documents
      def transform_by_map(doc, m)
        m.keys.inject({}) do |new_doc, k|
          val = find_value_in_document(doc, k)
          val ? insert_value_in_document(new_doc, m[k], val) : new_doc
        end
      end

      def transform_by_inverted_map(doc, m)
        inverted = m.keys.inject({}) do |ivm, k|
          ivm.merge(m[k] => k)
        end
        transform_by_map(doc, inverted)
      end

      def combine_documents(docs)
        docs.inject(nil) do |combined, doc|
          combined ? merge_document(combined, doc) : doc
        end
      end

      def merge_document(dest, src)
        src.keys.inject(dest) do |final, k|
          if src[k].class == Hash
            existing = final.fetch(k, {})
            existing = {} if existing.class != Hash
            final.merge(k => merge_document(existing, src[k]))
          elsif src[k].class == Array && dest[k].class == Array
            merged_a = src[k].each_with_index.map do |o, i|
              merge_document(dest[k][i], o)
            end
            
            final.merge(k => merged_a)
          else
            final.merge(k => src[k])
          end
        end
      end

      def document_contains_path(doc, k)
        do_contains(doc, k.split('.'))
      end

      def extract_corresponding(doc, assoc_doc)
        assoc_doc.keys.inject({}) do |corr, k|
          if doc.key?(k)
            if doc[k].class == Hash
              corr.merge(k => extract_corresponding(doc[k], assoc_doc.fetch(k, {})))
            elsif doc[k].class == Array && assoc_doc[k].class == Array
              # TODO: assumes that assoc_doc is dominant in size
              subset = assoc_doc[k].each_with_index.map do |val, i|
                extract_corresponding(doc[k][i], val)
              end
              corr.merge(k => subset)
            else
              corr.merge(k => doc[k])
            end
          else
            corr
          end
        end
      end
      
      private

      def find_value_in_document(doc, ks)
        parts = ks.split('.')
        len = parts.length
        
        (0...len).inject(doc) { |o, i| o.fetch(parts[i], (i == len - 1) ? nil : {}) }        
      end

      def insert_value_in_document(doc, ks, val)
        do_insertion(doc, ks.split('.'), val)
      end

      def do_insertion(doc, ks, val)
        doc.merge(ks.first => ks.length == 1 ? val : do_insertion(doc.fetch(ks.first, {}), ks[1..-1], val))
      end

      def do_contains(doc, ks)
        ks.length == 1 ? doc.include?(ks.first) : do_contains(doc.fetch(ks.first), ks[1..-1])
      end
    end
  end
end
