export const typeDefs = /* GraphQL */ `
  "Agrupacion del menu: cafe caliente, cafe frio, reposteria."
  type Categoria {
    id: ID!
    nombre: String!
    descripcion: String!
    productos: [Producto!]!
  }

  "Bebida o alimento que se puede pedir."
  type Producto {
    id: ID!
    nombre: String!
    descripcion: String!
    precio: Float!
    disponible: Boolean!
    creadoEn: String!
    categoria: Categoria
  }

  input ProductoEntrada {
    nombre: String!
    descripcion: String
    precio: Float!
    categoriaId: ID!
    disponible: Boolean
  }

  type Query {
    "El menu completo. Con soloDisponibles se ocultan los agotados."
    productos(soloDisponibles: Boolean = false, categoriaId: ID): [Producto!]!
    producto(id: ID!): Producto
    categorias: [Categoria!]!
  }

  type Mutation {
    "Solo Admin."
    crearProducto(entrada: ProductoEntrada!): Producto!
    "Solo Admin. Marca un producto como agotado o disponible."
    cambiarDisponibilidad(id: ID!, disponible: Boolean!): Producto!
  }
`;
