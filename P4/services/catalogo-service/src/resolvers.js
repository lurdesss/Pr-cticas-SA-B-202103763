import { GraphQLError } from 'graphql';
import { repositorio } from './repositorio.js';

// El gateway ya verifico que el rol tenga el permiso catalogo:usar. Aqui se
// vuelve a comprobar el rol para las mutaciones porque GraphQL expone un
// solo endpoint: leer y escribir viajan por la misma URL, asi que la
// granularidad fina tiene que vivir en el resolver.
function exigirAdmin(contexto) {
  if (contexto.rol !== 'admin') {
    throw new GraphQLError('Esta operacion requiere el rol Admin.', {
      extensions: { code: 'FORBIDDEN', http: { status: 403 } },
    });
  }
}

function exigirEncontrado(valor, mensaje) {
  if (!valor) {
    throw new GraphQLError(mensaje, { extensions: { code: 'NOT_FOUND', http: { status: 404 } } });
  }
  return valor;
}

export const resolvers = {
  Query: {
    productos: (_padre, argumentos) =>
      repositorio.listarProductos({
        soloDisponibles: argumentos.soloDisponibles ?? false,
        categoriaId: argumentos.categoriaId ? Number(argumentos.categoriaId) : null,
      }),
    producto: (_padre, { id }) => repositorio.productoPorId(Number(id)),
    categorias: () => repositorio.listarCategorias(),
  },

  Mutation: {
    crearProducto: async (_padre, { entrada }, contexto) => {
      exigirAdmin(contexto);
      if (entrada.precio < 0) {
        throw new GraphQLError('El precio no puede ser negativo.', {
          extensions: { code: 'BAD_USER_INPUT', http: { status: 400 } },
        });
      }
      const categoria = await repositorio.categoriaPorId(Number(entrada.categoriaId));
      exigirEncontrado(categoria, 'Esa categoria no existe.');
      return repositorio.crearProducto({ ...entrada, categoriaId: Number(entrada.categoriaId) });
    },

    cambiarDisponibilidad: async (_padre, { id, disponible }, contexto) => {
      exigirAdmin(contexto);
      const producto = await repositorio.cambiarDisponibilidad(Number(id), disponible);
      return exigirEncontrado(producto, 'Ese producto no existe.');
    },
  },

  Categoria: {
    productos: (categoria) => repositorio.listarProductos({ categoriaId: Number(categoria.id) }),
  },

  Producto: {
    categoria: (producto) => repositorio.categoriaPorId(Number(producto.categoriaId)),
  },
};
