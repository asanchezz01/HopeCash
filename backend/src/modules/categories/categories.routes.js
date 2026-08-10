import { Router } from 'express';
import { crudRouter } from '../../core/crudRouter.js';
import { syncRepo } from '../../core/syncRepo.js';
import { notFound, HttpError } from '../../utils/httpError.js';
import { categoryInUse } from './categories.service.js';

const router = Router();

router.get('/:categoryId/subcategories', async (req, res) => {
  const category = await syncRepo.findById('categories', req.auth, req.params.categoryId);
  if (!category) throw notFound('Categoria não encontrada');
  const subs = await syncRepo.list('subcategories', req.auth, {
    limit: 200, filters: { category_id: category.id },
  });
  res.json({ data: subs });
});

router.use('/subcategories', crudRouter('subcategories', { filterFields: ['category_id'] }));

// Só podem ser excluídas categorias sem lançamentos e sem orçamentos.
router.delete('/:id', async (req, res) => {
  const category = await syncRepo.findById('categories', req.auth, req.params.id);
  if (!category) throw notFound('Categoria não encontrada');
  if (await categoryInUse(category.id)) {
    throw new HttpError(409, 'CATEGORY_IN_USE',
      'Categoria possui lançamentos ou orçamentos e não pode ser excluída');
  }
  const result = await syncRepo.softDelete('categories', req.auth, category.id, { req });
  res.json({ data: result });
});

router.use('/', crudRouter('categories', { filterFields: ['type'] }));

export default router;
