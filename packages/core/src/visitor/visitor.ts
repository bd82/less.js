// import tree from '../tree';
const _visitArgs = { visitDeeper: true };
let _hasIndexed = false;

function _noop(node) {
    return node;
}

class Visitor {
    constructor() {
        this._visitInCache = {};
        this._visitOutCache = {};

        if (!_hasIndexed) {
            indexNodeTypes(tree, 1);
            _hasIndexed = true;
        }
    }

    visit(node) {
        if (!node) {
            return node;
        }

        const nodeTypeIndex = node.typeIndex;
        if (!nodeTypeIndex) {
            // MixinCall args aren't a node type?
            if (node.value && node.value.typeIndex) {
                this.visit(node.value);
            }
            return node;
        }

        const impl = this._implementation;
        let func = this._visitInCache[nodeTypeIndex];
        let funcOut = this._visitOutCache[nodeTypeIndex];
        const visitArgs = _visitArgs;
        let fnName;

        visitArgs.visitDeeper = true;

        if (!func) {
            fnName = `visit${node.type}`;
            func = impl[fnName] || _noop;
            funcOut = impl[`${fnName}Out`] || _noop;
            this._visitInCache[nodeTypeIndex] = func;
            this._visitOutCache[nodeTypeIndex] = funcOut;
        }

        if (func !== _noop) {
            const newNode = func.call(impl, node, visitArgs);
            if (node && impl.isReplacing) {
                node = newNode;
            }
        }

        if (visitArgs.visitDeeper && node && node.accept) {
            node.accept(this);
        }

        if (funcOut != _noop) {
            funcOut.call(impl, node);
        }

        return node;
    }

    visitArray(nodes, nonReplacing) {
        if (!nodes) {
            return nodes;
        }

        const cnt = nodes.length;
        let i;

        // Non-replacing
        if (nonReplacing || !this._implementation.isReplacing) {
            for (i = 0; i < cnt; i++) {
                this.visit(nodes[i]);
            }
            return nodes;
        }

        // Replacing
        const out = [];
        for (i = 0; i < cnt; i++) {
            const evald = this.visit(nodes[i]);
            if (evald === undefined) {
                continue;
            }
            if (!evald.splice) {
                out.push(evald);
            } else if (evald.length) {
                this.flatten(evald, out);
            }
        }
        return out;
    }

    flatten(arr, out) {
        if (!out) {
            out = [];
        }

        let cnt;
        let i;
        let item;
        let nestedCnt;
        let j;
        let nestedItem;

        for (i = 0, cnt = arr.length; i < cnt; i++) {
            item = arr[i];
            if (item === undefined) {
                continue;
            }
            if (!item.splice) {
                out.push(item);
                continue;
            }

            for (j = 0, nestedCnt = item.length; j < nestedCnt; j++) {
                nestedItem = item[j];
                if (nestedItem === undefined) {
                    continue;
                }
                if (!nestedItem.splice) {
                    out.push(nestedItem);
                } else if (nestedItem.length) {
                    this.flatten(nestedItem, out);
                }
            }
        }

        return out;
    }
}

export default Visitor;